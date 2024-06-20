#!/bin/bash

set -e -uxf -o pipefail

# Function to check if a service is healthy
check_service_health() {
  local service_name=$1
  local url=$2
  local retry_count=10
  local wait_seconds=5

  echo "Checking health of service: $service_name at $url"
  
  for i in $(seq 1 $retry_count); do
    if curl -s -L --head --request GET "$url" | grep "200 OK" > /dev/null; then
      echo "$service_name is healthy"
      return 0
    else
      echo "Waiting for $service_name to be healthy... ($i/$retry_count)"
      sleep $wait_seconds
    fi
  done

  echo "Error: $service_name did not become healthy in time"
  return 1
}

# Function to check if all services are healthy
wait_for_services() {
  echo "Waiting for services to be up and running..."
  check_service_health "Jaeger" "http://localhost:16686"
  check_service_health "Prometheus" "http://localhost:9090/graph"
  check_service_health "Grafana" "http://localhost:3000"
}
# Function to check SPM
check_spm(){
  local attempt=0
  local max_attempts=60
  local wait_seconds=5

  echo "Checking spm"
  services_list=("driver" "customer" "mysql" "redis" "frontend" "route" "ui" )
  for service in "${services_list[@]}"; do
  echo "Processing service: $service"
     while (( attempt <= max_attempts )); do
      response=$(curl -s "http://localhost:16686/api/metrics/calls?service=$service&endTs=$(date +%s)000&lookback=1000&step=100&ratePer=60000")
      service_name=$(echo "$response" | jq -r 'if .metrics and .metrics[0] then .metrics[0].labels[] | select(.name=="service_name") | .value else empty end')
      if [ "$service_name" != "$service" ]; then
        echo "Service name does not match 'driver'"
        attempt=$(( attempt + 1 ))
        sleep $wait_seconds
      else
        echo "Service name matched with 'driver'"
        break
      fi
  done
    
    all_non_zero=true
    metric_points=$(echo "$response" | jq -r '.metrics[0].metricPoints[] | .gaugeValue.doubleValue')
    # Check if metric points are empty
    if [ -z "$metric_points" ]; then
      echo "Metric points for service $service are empty"
      exit 1
    fi
    for value in $metric_points; do
      if [[ "$value" == "0" || "$value" == "0.0" ]]; then
        all_non_zero=false
        break
      fi
    done
    
    if [ "$all_non_zero" = true ]; then
      echo "All gauge values are non-zero"
    else
      echo "Some gauge values are zero"
      exit 1
    fi
  done
  
}

# Function to tear down Docker Compose services
teardown_services() {
 docker compose -f docker-compose/monitor/docker-compose.yml down
}

# Main function
main() {
  (cd docker-compose/monitor && make build && make dev  ARGS="-d")
  wait_for_services
  check_spm
  echo "All services are running correctly"
}
trap teardown_services EXIT INT
# Run the main function
main

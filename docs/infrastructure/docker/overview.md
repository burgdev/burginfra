---
title: Docker Compose
order: 0
---

## Common Docker Compose Commands

### Basic Operations
- `docker compose up` - Start all services defined in docker-compose.yml
- `docker compose up -d` - Start services in detached mode (background)
- `docker compose down` - Stop and remove containers, networks, and volumes
- `docker compose ps` - List running containers
- `docker compose logs` - View output from containers
- `docker compose logs -f` - Follow log output

### Service Management
- `docker compose start [service]` - Start a specific service
- `docker compose stop [service]` - Stop a specific service
- `docker compose restart [service]` - Restart a specific service
- `docker compose pause [service]` - Pause a service
- `docker compose unpause [service]` - Unpause a service

### Build and Configuration
- `docker compose build` - Build or rebuild services
- `docker compose build --no-cache` - Build without using cache
- `docker compose config` - Validate and view the Compose file
- `docker compose pull` - Pull latest images for services

### Debugging and Maintenance
- `docker compose exec [service] [command]` - Execute a command in a running container
- `docker compose run [service] [command]` - Run a one-off command on a service
- `docker compose top` - Display running processes
- `docker compose images` - List images used by the created containers

### Cleanup
- `docker compose down -v` - Remove volumes when stopping containers
- `docker compose down --rmi all` - Remove all images used by services
- `docker compose rm` - Remove stopped containers

### Scaling
- `docker compose up --scale [service]=[num]` - Scale a service to multiple instances

### Environment Variables
- `docker-compose --env-file .env up` - Use a specific .env file

> Note: Most commands can be run with `-f` flag to specify a custom compose file, e.g., `docker-compose -f docker-compose.prod.yml up`


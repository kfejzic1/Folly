# Running Folly with Podman Compose

This guide covers running the full Folly stack (Ollama + API + UI) using `podman-compose`.

## Prerequisites

- [Podman](https://podman.io/) installed
- [podman-compose](https://github.com/containers/podman-compose) installed (`pip install podman-compose`)

### GPU Acceleration (Linux only)

GPU acceleration is supported via NVIDIA GPUs. To enable it, you need the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) (CDI) configured for Podman. On Linux, run the following to install and configure it:

```bash
# Install the NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit

# Generate the CDI specification so Podman can discover the GPU
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# Verify the GPU is visible to Podman
podman run --rm --device nvidia.com/gpu=all docker.io/nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```

If you do not have an NVIDIA GPU or the toolkit installed, remove the `devices` section from the `ollama` service in `docker-compose.yml` to run with CPU-only inference.

## Architecture

The stack consists of four services:

| Service       | Role                                                                                     |
| ------------- | ---------------------------------------------------------------------------------------- |
| `ollama`      | Runs the Ollama inference server with GPU access                                         |
| `ollama-pull` | One-shot container that waits for Ollama to be ready, then pulls the configured model    |
| `folly-api`   | Polls Ollama until the model is available, then starts the Folly API server on port 5000 |
| `folly-ui`    | Starts the Folly web UI on port 5001                                                     |

When everything is running, you should see **3 running containers** (`ollama`, `folly-api`, `folly-ui`) and **1 exited container** (`ollama-pull`, exit code 0). The `ollama-pull` service is a one-shot container that terminates after the model has been successfully pulled.

## Running the Application

### Basic Usage

```bash
podman-compose up --build -d
```

This builds the Folly images, pulls the default model (`llama3.1`), and starts all services in the background. The UI will be available at **http://localhost:5001** once all services are ready.

### Using a Different Model (Optional)

Set the `OLLAMA_MODEL` environment variable:

```bash
OLLAMA_MODEL=mistral
```

Or on PowerShell:

```powershell
$env:OLLAMA_MODEL="mistral";
```

## Viewing Logs

### All Services

```bash
podman-compose logs
```

### Follow Logs in Real Time

```bash
podman-compose logs -f
```

### Logs for a Specific Service

```bash
podman-compose logs folly-api
podman-compose logs -f ollama
```

### Checking Startup Progress

During startup, the services log their wait status. You can monitor the boot sequence with:

```bash
podman-compose logs -f ollama-pull folly-api
```

You should see messages like:

```
ollama-pull  | Waiting for Ollama to be ready...
ollama-pull  | Model pulled successfully.
folly-api    | Waiting for model llama3.1 to be available...
folly-api    | Model ready, starting API...
```

## Debugging

### Checking Service Status

```bash
podman-compose ps
```

You should see 3 running containers (`ollama`, `folly-api`, `folly-ui`) and 1 exited container (`ollama-pull` with exit code 0). If `ollama-pull` shows a non-zero exit code, check its logs to see what went wrong.

### Opening a Shell in a Running Container

```bash
podman-compose exec folly-api /bin/sh
podman-compose exec ollama /bin/sh
```

### Testing Ollama Directly

```bash
# Check if Ollama is responding
podman-compose exec ollama ollama list

# Manually pull a model
podman-compose exec ollama ollama pull llama3.1
```

### Testing the API Directly

```bash
podman-compose exec folly-api python3 -c "
import urllib.request, json
resp = urllib.request.urlopen('http://ollama:11434/api/tags')
print(json.loads(resp.read()))
"
```

If you need to expose the API port to the host for debugging, add a `ports` mapping to the `folly-api` service in `docker-compose.yml`:

```yaml
folly-api:
  ports:
    - '5000:5000'
```

### Common Issues

**Services exit immediately:** Check logs with `podman-compose logs <service>` to see the error output.

**Model pull is slow or fails:** The first run downloads the full model (several GB). Ensure you have enough disk space and a stable network connection. The model is cached in the `ollama_data` volume for subsequent runs.

**GPU not detected:** Ensure the NVIDIA Container Toolkit is installed and the CDI spec is generated. See the [GPU Acceleration](#gpu-acceleration-linux-only) section.

## Cleanup

To remove everything created by this project (containers, images, volumes, and networks):

```bash
podman-compose down                                        # stop and remove all project containers
podman rmi folly_folly-api folly_folly-ui                  # remove the built Folly images
podman rmi docker.io/ollama/ollama                         # remove the Ollama image
podman volume rm folly_ollama_data                         # remove the volume with downloaded models
podman network rm folly_folly-net                          # remove the project network
```

> **Note:** Removing the `folly_ollama_data` volume deletes all cached models. They will need to be re-downloaded on the next run.

# MSSQL Proxy

FastAPI proxy for SQL Server queries using Windows authentication. Runs on the Windows host so it has access to Windows/domain credentials. Containers hit it via `host.docker.internal:9999`.

## Setup

### Quick start (from WSL)

```bash
# Add alias (one-time)
echo 'alias mssql-proxy="cmd.exe /c \"pushd \\\\\\\\wsl\$\\\\Ubuntu\\\\home\\\\kschepis\\\\workspaces\\\\mpulse\\\\.tools\\\\mssql-proxy && start.bat\""' >> ~/.bashrc
source ~/.bashrc

# Start it
mssql-proxy
```

### Manual start (from Windows)

```powershell
cd \\wsl$\Ubuntu\home\kschepis\workspaces\mpulse\.tools\mssql-proxy
pip install -r requirements.txt
python server.py
```

## Usage

```bash
# From container
curl -X POST http://host.docker.internal:9999/query \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT TOP 5 * FROM sys.tables", "connection": "dp_config"}'

# Health check
curl http://host.docker.internal:9999/health

# List connections
curl http://host.docker.internal:9999/connections
```

## Configuration

Edit `connections.toml` to add SQL Server connections. Restart the proxy after changes.

## Why host-side?

SQL Server uses Windows Integrated Auth (Trusted_Connection). This requires Windows credentials which aren't available inside Linux containers. The proxy runs on the host with native Windows auth and exposes a simple HTTP API.

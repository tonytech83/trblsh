# trblsh

### Target setup

- Alloy
- Node_Exporter

Install alloy and node_exporter on target

```ah
curl -fsSL https://raw.githubusercontent.com/tonytech83/trblsh/master/target-setup.sh | bash
```

### Up and running trblsh containers

```sh
docker compose up -d
```

3. Delete all trblsh containers

```sh
docker compose down -v
```

4. running from troubleshooter folder

```sh
uv run uvicorn app:app --host 0.0.0.0 --port 8080
```

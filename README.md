# trblsh

1. Install alloy on target

```ah
curl -fsSL https://raw.githubusercontent.com/tonytech83/trblsh/master/setup.sh | bash
```

2. Up and running trblsh containers

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

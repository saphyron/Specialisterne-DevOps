# Fra repo-root:
copy .env.sample .env   # hvis du laver en sample
notepad .env            # sæt stærke værdier

docker compose up -d --build
curl http://localhost:8080/auth/health
docker compose logs -f db
docker compose logs -f api

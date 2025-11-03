# Build
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# csproj ligger i: Cereal API/Cereal API/Cereal API.csproj
COPY ["Cereal API/Cereal API/Cereal API.csproj", "Cereal API/Cereal API/"]
RUN dotnet restore "Cereal API/Cereal API/Cereal API.csproj"

# resten af koden
COPY . .
WORKDIR "/app/Cereal API/Cereal API"
RUN dotnet publish -c Release -o /app/publish /p:UseAppHost=false

# Runtime
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final
WORKDIR /app
COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "Cereal API.dll"]

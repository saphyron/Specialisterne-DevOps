# Build stage
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Kopiér csproj (med mellemrum i stier) og restore som separat lag
COPY ["Cereal API/Cereal API/Cereal API.csproj", "Cereal API/Cereal API/"]
RUN dotnet restore "Cereal API/Cereal API/Cereal API.csproj"

# Kopiér resten af koden
COPY . .

# Gå til projektmappen og publish til /out
WORKDIR "/src/Cereal API/Cereal API"
RUN dotnet publish -c Release -o /out /p:UseAppHost=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final
WORKDIR /app
COPY --from=build /out .

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "Cereal API.dll"]

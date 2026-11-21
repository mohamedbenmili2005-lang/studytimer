# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY StudyTimer.slnx ./
COPY StudyTimer.Domain/StudyTimer.Domain.csproj StudyTimer.Domain/
COPY StudyTimer.Infrastructure/StudyTimer.Infrastructure.csproj StudyTimer.Infrastructure/
COPY StudyTimer.Api/StudyTimer.Api.csproj StudyTimer.Api/
RUN dotnet restore StudyTimer.Api/StudyTimer.Api.csproj
COPY . .
RUN dotnet publish StudyTimer.Api/StudyTimer.Api.csproj -c Release -o /app --no-restore -p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
COPY --from=build /app .
ENV ASPNETCORE_URLS=http://+:8080 \
    ASPNETCORE_ENVIRONMENT=Production \
    Database__MigrateOnStart=true
USER $APP_UID
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD curl -fs http://localhost:8080/health || exit 1
ENTRYPOINT ["dotnet", "StudyTimer.Api.dll"]

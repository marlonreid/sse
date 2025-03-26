FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY . .
RUN dotnet publish -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:9.0
WORKDIR /app
COPY --from=build /app .

# Linux optimizations
RUN apt-get update && \
    apt-get install -y libuv1-dev && \
    rm -rf /var/lib/apt/lists/*

ENV ASPNETCORE_URLS=http://*:8080
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV COMPlus_EnableDiagnostics=0

ENTRYPOINT ["dotnet", "YourApp.dll"]

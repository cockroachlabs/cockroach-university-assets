#!/bin/bash
set -euxo pipefail

# Per-language setup for "CockroachDB for .NET Developers" labs.
# Usage: dotnet.sh [connect|resilient]
# Installs the .NET 10 SDK (the library packages target net10.0), then lays down
# a console project wired to the public CockroachDB .NET library Pages NuGet feed.

LAB=${1:-connect}
DOTNET_CHANNEL=${DOTNET_CHANNEL:-10.0}

# --- Install the .NET SDK ----------------------------------------------------
if ! dotnet --version 2>/dev/null | grep -q '^10\.'; then
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    bash /tmp/dotnet-install.sh --channel "${DOTNET_CHANNEL}" --install-dir /usr/share/dotnet
    ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet
fi
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
export PATH=$PATH:/usr/share/dotnet
grep -q '/usr/share/dotnet' ~/.bashrc || echo 'export PATH=$PATH:/usr/share/dotnet' >> ~/.bashrc

mkdir -p /root/app && cd /root/app
[ -f app.csproj ] || dotnet new console --name app --output . --force

# --- CockroachDB .NET library: public Pages NuGet feed (anonymous, no token) --
dotnet nuget add source "https://cockroachlabs.github.io/cockroachdb-dotnet-library/nuget/index.json" \
  -n cockroachlabs || true
dotnet add package CockroachDB.DotNet.Core --version 1.0.1 || true
dotnet add package Npgsql || true
# Concrete DI container + configuration (AddCockroachDB takes IConfiguration and
# registers into an IServiceCollection; these provide the concrete types).
dotnet add package Microsoft.Extensions.DependencyInjection || true
dotnet add package Microsoft.Extensions.Configuration || true
# The library's middleware (e.g. RetryMiddleware) takes ILogger<T>, so the app
# must register logging in its service collection.
dotnet add package Microsoft.Extensions.Logging || true

if [ "$LAB" = "resilient" ]; then
    cockroach sql --insecure --host=localhost:26257 -d defaultdb -e \
      "CREATE TABLE IF NOT EXISTS accounts (id INT PRIMARY KEY, balance INT); UPSERT INTO accounts VALUES (1, 1000), (2, 1000);" || true
    cat > /root/app/Program.cs <<'CS'
using CockroachDB.DotNet.Core.Extensions;
using CockroachDB.DotNet.Abstractions.Template;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Npgsql;

// All three nodes are listed (host:port pairs), so the driver fails over if one dies.
var cs = "Host=localhost:26257,localhost:26258,localhost:26259;Database=defaultdb;Username=root;SSL Mode=Disable;";
await using var dataSource = NpgsqlDataSource.Create(cs);

// AddCockroachDB registers the template + pipeline; UseRetry retries 40001 for us.
var services = new ServiceCollection();
services.AddLogging();
services.AddCockroachDB(new ConfigurationBuilder().Build(), b => b.UseRetry());
var template = services.BuildServiceProvider().GetRequiredService<ICockroachDBTemplate>();

int n = 0;
while (true)
{
    try
    {
        await template.ExecuteAsync(async () =>
        {
            await using var conn = await dataSource.OpenConnectionAsync();
            await using var tx = await conn.BeginTransactionAsync();
            await using (var c1 = new NpgsqlCommand("UPDATE accounts SET balance = balance - 1 WHERE id = 1", conn, tx))
                await c1.ExecuteNonQueryAsync();
            await using (var c2 = new NpgsqlCommand("UPDATE accounts SET balance = balance + 1 WHERE id = 2", conn, tx))
                await c2.ExecuteNonQueryAsync();
            await tx.CommitAsync();
        });
        n++;
        if (n % 20 == 0) Console.WriteLine($"ok: {n} transfers (app still serving)");
    }
    catch (Exception e)
    {
        Console.WriteLine($"ERROR (not retried away): {e.Message}");
    }
    await Task.Delay(100);
}
CS
else
    # Skeleton: opens a data source and a connection on startup, so Ch1 ("boot
    # and connect") passes on a plain run — its check greps "connected to
    # CockroachDB". The learner adds the first query in Ch2.
    cat > /root/app/Program.cs <<'CS'
using Npgsql;

var cs = "Host=localhost;Port=26257;Database=defaultdb;Username=root;SSL Mode=Disable;";
await using var dataSource = NpgsqlDataSource.Create(cs);
await using var conn = await dataSource.OpenConnectionAsync();
Console.WriteLine("connected to CockroachDB");
CS
fi

dotnet restore || true
dotnet build -c Debug || true   # pre-build so the first `dotnet run` in checks is fast
echo "[INFO] .NET lab assets ready (${LAB})"

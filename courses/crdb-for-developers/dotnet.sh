#!/bin/bash
set -euxo pipefail

# Per-language setup for "CockroachDB for .NET Developers" labs.
# Usage: dotnet.sh [connect|resilient]
# Requires GH_USER / GH_PAT (Instruqt track variables) while the library is pre-release.
# ASSUMPTION: .NET SDK channel 8.0 (LTS). Bump --channel if the library targets newer.

LAB=${1:-connect}

# --- Install the .NET SDK ----------------------------------------------------
if ! command -v dotnet &>/dev/null; then
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    bash /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet
    ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet
fi
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

mkdir -p /root/app && cd /root/app
[ -f app.csproj ] || dotnet new console --name app --output . --force

# --- Strategy B: NuGet via GitHub Packages ----------------------------------
# PUBLIC-SWAP: after GA, drop the github source and use the public nuget.org feed.
dotnet nuget add source "https://nuget.pkg.github.com/felipeg48/index.json" \
  -n github -u "${GH_USER}" -p "${GH_PAT}" --store-password-in-clear-text || true
dotnet add package CockroachDB.DotNet.Core || true
dotnet add package Npgsql || true

if [ "$LAB" = "resilient" ]; then
    cockroach sql --insecure --host=localhost:26257 -d defaultdb -e \
      "CREATE TABLE IF NOT EXISTS accounts (id INT PRIMARY KEY, balance INT); UPSERT INTO accounts VALUES (1, 1000), (2, 1000);" || true
    cat > /root/app/Program.cs <<'CS'
using Npgsql;

// All three nodes are listed, so the driver fails over if one goes down.
var cs = "Host=localhost,localhost,localhost;Port=26257,26258,26259;Database=defaultdb;Username=root;SSL Mode=Disable;";
await using var dataSource = NpgsqlDataSource.Create(cs);

int n = 0;
while (true)
{
    try
    {
        await using var conn = await dataSource.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();
        await using (var c1 = new NpgsqlCommand("UPDATE accounts SET balance = balance - 1 WHERE id = 1", conn, tx))
            await c1.ExecuteNonQueryAsync();
        await using (var c2 = new NpgsqlCommand("UPDATE accounts SET balance = balance + 1 WHERE id = 2", conn, tx))
            await c2.ExecuteNonQueryAsync();
        await tx.CommitAsync();
        n++;
        if (n % 20 == 0) Console.WriteLine($"ok: {n} transfers (app still serving)");
    }
    catch (Exception e)
    {
        // In an ASP.NET host, AddCockroachDB(...).UseRetry() retries 40001 for you;
        // this console loop surfaces the error so you can see failover happening.
        Console.WriteLine($"ERROR (not retried away): {e.Message}");
    }
    await Task.Delay(100);
}
CS
else
    cat > /root/app/Program.cs <<'CS'
using Npgsql;

var cs = "Host=localhost;Port=26257;Database=defaultdb;Username=root;SSL Mode=Disable;";
await using var dataSource = NpgsqlDataSource.Create(cs);

// You'll add your first query here during the challenges.
Console.WriteLine("connected to CockroachDB");
CS
fi

dotnet restore || true
echo "[INFO] .NET lab assets ready (${LAB})"

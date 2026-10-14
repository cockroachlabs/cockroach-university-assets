#!/bin/bash
set -euxo pipefail

# Per-language setup for "CockroachDB for Go Developers" labs.
# Usage: go.sh [connect|resilient]
# Requires GH_USER / GH_PAT (Instruqt track variables) while the library is pre-release.

LAB=${1:-connect}
GO_VER=${GO_VER:-1.26.3}

# --- Install Go --------------------------------------------------------------
if ! command -v go &>/dev/null; then
    curl -fsSL "https://go.dev/dl/go${GO_VER}.linux-amd64.tar.gz" -o /tmp/go.tgz
    rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tgz && rm -f /tmp/go.tgz
fi
export PATH=$PATH:/usr/local/go/bin
grep -q '/usr/local/go/bin' ~/.bashrc || echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc

# --- Strategy B: private module fetch via git + PAT --------------------------
# PUBLIC-SWAP: after GA, drop the git credential rewrite and GOPRIVATE.
set +x   # do not echo the token into the setup log
git config --global url."https://${GH_USER}:${GH_PAT}@github.com/".insteadOf "https://github.com/"
set -x
export GOPRIVATE="github.com/felipeg48/*"
grep -q 'GOPRIVATE' ~/.bashrc || echo 'export GOPRIVATE=github.com/felipeg48/*' >> ~/.bashrc

mkdir -p /root/app && cd /root/app
[ -f go.mod ] || go mod init crdblab

# Pre-pull the library + pgx into go.mod and the module cache (no `go mod tidy`,
# which would prune the library from the connect starter that doesn't import it yet).
set +x   # the git credential rewrite above already injected the token; keep it out of logs
go get github.com/felipeg48/cockroachdb-go-library || true
go get github.com/jackc/pgx/v5 || true
set -x

if [ "$LAB" = "resilient" ]; then
    cockroach sql --insecure --host=localhost:26257 -d defaultdb -e \
      "CREATE TABLE IF NOT EXISTS accounts (id INT PRIMARY KEY, balance INT); UPSERT INTO accounts VALUES (1, 1000), (2, 1000);" || true
    cat > /root/app/main.go <<'GO'
package main

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/felipeg48/cockroachdb-go-library/crdbgo"
	"github.com/felipeg48/cockroachdb-go-library/crdbgo/pgxadapter"
)

func main() {
	ctx := context.Background()
	// All three nodes are listed, so the driver fails over if one goes down.
	dsn := "postgresql://root@localhost:26257,localhost:26258,localhost:26259/defaultdb?sslmode=disable"
	pool, err := pgxadapter.NewPool(ctx, dsn, []crdbgo.Option{
		crdbgo.WithMaxRetries(10), crdbgo.WithJitter(true),
	})
	if err != nil {
		panic(err)
	}
	defer pool.Close()

	n := 0
	for {
		err := pool.ExecuteTx(ctx, func(tx pgx.Tx) error {
			if _, e := tx.Exec(ctx, "UPDATE accounts SET balance = balance - 1 WHERE id = 1"); e != nil {
				return e
			}
			_, e := tx.Exec(ctx, "UPDATE accounts SET balance = balance + 1 WHERE id = 2")
			return e
		})
		if err != nil {
			fmt.Printf("ERROR (not retried away): %v\n", err)
		} else {
			n++
			if n%20 == 0 {
				fmt.Printf("ok: %d transfers (app still serving)\n", n)
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
}
GO
else
    cat > /root/app/main.go <<'GO'
package main

import "fmt"

func main() {
	// Open a pool with pgxadapter.NewPool during the challenges, then run a query.
	fmt.Println("TODO: connect to CockroachDB")
}
GO
fi

echo "[INFO] Go lab assets ready (${LAB})"

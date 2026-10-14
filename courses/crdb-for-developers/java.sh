#!/bin/bash
set -euxo pipefail

# Per-language setup for "CockroachDB for Java Developers" labs.
# Usage: java.sh [connect|resilient]
# Expects a JDK already installed (the track pulls base/ubuntu-jvm-21.sh first).
# Requires GH_USER / GH_PAT (Instruqt track variables) while the library is pre-release.
# ASSUMPTION: JDK 21 + Maven. The library targets Java 25 — verify on first test.

LAB=${1:-connect}

DEBIAN_FRONTEND=noninteractive apt -y install maven || true

# --- Strategy B: Maven via GitHub Packages ----------------------------------
# PUBLIC-SWAP: after GA, drop this server block and the GitHub Packages repo in pom.xml.
mkdir -p ~/.m2
cat > ~/.m2/settings.xml <<EOF
<settings>
  <servers>
    <server>
      <id>github</id>
      <username>${GH_USER}</username>
      <password>${GH_PAT}</password>
    </server>
  </servers>
</settings>
EOF

mkdir -p /root/app/src/main/java && cd /root/app
cat > /root/app/pom.xml <<'XML'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>crdblab</artifactId>
  <version>1.0</version>
  <properties><maven.compiler.release>21</maven.compiler.release></properties>
  <repositories>
    <repository>
      <id>github</id>
      <url>https://maven.pkg.github.com/felipeg48/cockroachdb-java-library</url>
    </repository>
  </repositories>
  <dependencies>
    <dependency>
      <groupId>com.cockroachlabs</groupId>
      <artifactId>cockroachdb-java-library-core</artifactId>
      <version>LATEST</version>
    </dependency>
    <dependency>
      <groupId>org.postgresql</groupId>
      <artifactId>postgresql</artifactId>
      <version>42.7.3</version>
    </dependency>
  </dependencies>
  <build>
    <plugins>
      <plugin>
        <groupId>org.codehaus.mojo</groupId>
        <artifactId>exec-maven-plugin</artifactId>
        <version>3.1.0</version>
        <configuration><mainClass>App</mainClass></configuration>
      </plugin>
    </plugins>
  </build>
</project>
XML

if [ "$LAB" = "resilient" ]; then
    cockroach sql --insecure --host=localhost:26257 -d defaultdb -e \
      "CREATE TABLE IF NOT EXISTS accounts (id INT PRIMARY KEY, balance INT); UPSERT INTO accounts VALUES (1, 1000), (2, 1000);" || true
    cat > /root/app/src/main/java/App.java <<'JAVA'
import com.cockroachlabs.crdb.Crdb;
import org.postgresql.ds.PGSimpleDataSource;
import javax.sql.DataSource;

public class App {
    public static void main(String[] args) throws Exception {
        PGSimpleDataSource ds = new PGSimpleDataSource();
        // All three nodes are listed, so the driver fails over if one goes down.
        ds.setUrl("jdbc:postgresql://localhost:26257,localhost:26258,localhost:26259/defaultdb?sslmode=disable&user=root");
        int n = 0;
        while (true) {
            try {
                Crdb.tx(ds, c -> {   // SERIALIZABLE + automatic retry on 40001
                    c.prepareStatement("UPDATE accounts SET balance = balance - 1 WHERE id = 1").executeUpdate();
                    c.prepareStatement("UPDATE accounts SET balance = balance + 1 WHERE id = 2").executeUpdate();
                    return null;
                });
                if (++n % 20 == 0) System.out.println("ok: " + n + " transfers (app still serving)");
            } catch (Exception e) {
                System.out.println("ERROR (not retried away): " + e.getMessage());
            }
            Thread.sleep(100);
        }
    }
}
JAVA
else
    cat > /root/app/src/main/java/App.java <<'JAVA'
import com.cockroachlabs.crdb.Crdb;
import org.postgresql.ds.PGSimpleDataSource;

public class App {
    public static void main(String[] args) throws Exception {
        PGSimpleDataSource ds = new PGSimpleDataSource();
        ds.setUrl("jdbc:postgresql://localhost:26257/defaultdb?sslmode=disable&user=root");
        // You'll add your first query here during the challenges.
        System.out.println("connected to CockroachDB");
    }
}
JAVA
fi

mvn -q -f /root/app/pom.xml dependency:go-offline || true
echo "[INFO] Java lab assets ready (${LAB})"

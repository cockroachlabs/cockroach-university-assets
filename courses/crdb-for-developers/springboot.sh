#!/bin/bash
set -euxo pipefail

# Per-language setup for "CockroachDB for Spring Boot Developers" labs.
# Usage: springboot.sh [connect|resilient]
# Expects a JDK already installed (the track pulls base/ubuntu-jvm-21.sh first).
# Requires GH_USER / GH_PAT (Instruqt track variables) while the starter is pre-release.
# ASSUMPTION: Spring Boot 4.x + Java 21. Starter coords com.cockroachlabs:cockroachdb-spring-boot-starter:0.1.0-SNAPSHOT.

LAB=${1:-connect}

DEBIAN_FRONTEND=noninteractive apt -y install maven || true

# --- Strategy B: Maven (GitHub Packages) credentials ------------------------
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

mkdir -p /root/app/src/main/java/demo /root/app/src/main/resources && cd /root/app
cat > /root/app/pom.xml <<'XML'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.4</version>
    <relativePath/>
  </parent>
  <groupId>com.example</groupId>
  <artifactId>crdblab</artifactId>
  <version>1.0</version>
  <properties><java.version>21</java.version></properties>
  <repositories>
    <repository>
      <id>github</id>
      <url>https://maven.pkg.github.com/felipeg48/cockroachdb-spring-boot-starter</url>
    </repository>
  </repositories>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-data-jpa</artifactId>
    </dependency>
    <dependency>
      <groupId>org.postgresql</groupId>
      <artifactId>postgresql</artifactId>
    </dependency>
    <dependency>
      <groupId>com.cockroachlabs</groupId>
      <artifactId>cockroachdb-spring-boot-starter</artifactId>
      <version>0.1.0-SNAPSHOT</version>
    </dependency>
  </dependencies>
  <build><plugins><plugin>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-maven-plugin</artifactId>
  </plugin></plugins></build>
</project>
XML

if [ "$LAB" = "resilient" ]; then
    HOSTS="localhost:26257,localhost:26258,localhost:26259"
    cockroach sql --insecure --host=localhost:26257 -d defaultdb -e \
      "CREATE TABLE IF NOT EXISTS accounts (id INT PRIMARY KEY, balance INT); UPSERT INTO accounts VALUES (1, 1000), (2, 1000);" || true
else
    HOSTS="localhost:26257"
fi
cat > /root/app/src/main/resources/application.properties <<PROPS
spring.datasource.url=jdbc:postgresql://${HOSTS}/defaultdb?sslmode=disable
spring.datasource.username=root
cockroachdb.retry.max-retries=10
PROPS

if [ "$LAB" = "resilient" ]; then
    cat > /root/app/src/main/java/demo/App.java <<'JAVA'
package demo;
import com.cockroachlabs.data.annotation.CockroachDB;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@SpringBootApplication
public class App {
    public static void main(String[] args) { SpringApplication.run(App.class, args); }
}

@Service
class Runner implements CommandLineRunner {
    private final Transfers transfers;
    Runner(Transfers t) { this.transfers = t; }
    public void run(String... args) throws Exception {
        int n = 0;
        while (true) {
            try { transfers.move(); if (++n % 20 == 0) System.out.println("ok: " + n + " transfers (app still serving)"); }
            catch (Exception e) { System.out.println("ERROR (not retried away): " + e.getMessage()); }
            Thread.sleep(100);
        }
    }
}

@Service
class Transfers {
    private final JdbcTemplate jdbc;
    Transfers(JdbcTemplate jdbc) { this.jdbc = jdbc; }
    @CockroachDB   // SERIALIZABLE transaction + automatic retry on 40001
    public void move() {
        jdbc.update("UPDATE accounts SET balance = balance - 1 WHERE id = 1");
        jdbc.update("UPDATE accounts SET balance = balance + 1 WHERE id = 2");
    }
}
JAVA
else
    cat > /root/app/src/main/java/demo/App.java <<'JAVA'
package demo;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class App {
    public static void main(String[] args) { SpringApplication.run(App.class, args); }
    // You'll add an entity, a repository, and your first query during the challenges.
}
JAVA
fi

mvn -q -f /root/app/pom.xml dependency:go-offline || true
echo "[INFO] Spring Boot lab assets ready (${LAB})"

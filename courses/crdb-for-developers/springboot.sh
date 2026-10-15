#!/bin/bash
set -euxo pipefail

# Per-language setup for "CockroachDB for Spring Boot Developers" labs.
# Usage: springboot.sh [connect|resilient]
# Installs Temurin JDK 21 (the starter targets Java 21 and Spring Boot 4.1) +
# Maven, then lays down a Spring Boot project wired to the CockroachDB Spring
# Boot starter on GitHub Packages.
# Requires GH_USER / GH_PAT (Instruqt secrets) while the starter is pre-release.

LAB=${1:-connect}
JDK_VER=${JDK_VER:-21}

# --- Install Maven, then Temurin JDK 21 as the system default ----------------
DEBIAN_FRONTEND=noninteractive apt -y install maven || true
if ! java -version 2>&1 | grep -q "version \"${JDK_VER}"; then
    curl -fsSL "https://api.adoptium.net/v3/binary/latest/${JDK_VER}/ga/linux/x64/jdk/hotspot/normal/eclipse" -o /tmp/jdk.tgz
    rm -rf "/opt/jdk-${JDK_VER}" && mkdir -p "/opt/jdk-${JDK_VER}"
    tar -C "/opt/jdk-${JDK_VER}" --strip-components=1 -xzf /tmp/jdk.tgz && rm -f /tmp/jdk.tgz
    update-alternatives --install /usr/bin/java  java  "/opt/jdk-${JDK_VER}/bin/java"  2100
    update-alternatives --install /usr/bin/javac javac "/opt/jdk-${JDK_VER}/bin/javac" 2100
    update-alternatives --set java  "/opt/jdk-${JDK_VER}/bin/java"
    update-alternatives --set javac "/opt/jdk-${JDK_VER}/bin/javac"
fi
export JAVA_HOME="/opt/jdk-${JDK_VER}"
grep -q 'JAVA_HOME=/opt/jdk' ~/.bashrc || echo "export JAVA_HOME=/opt/jdk-${JDK_VER}" >> ~/.bashrc

# --- Strategy B: Maven (GitHub Packages) credentials ------------------------
# PUBLIC-SWAP: after GA, drop this server block and the GitHub Packages repo in pom.xml.
mkdir -p ~/.m2
set +x   # do not echo the token into the setup log
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
set -x

mkdir -p /root/app/src/main/java/demo /root/app/src/main/resources && cd /root/app
# Spring Boot parent MUST match the version the starter was built against (4.1.1),
# otherwise the starter's auto-configuration resolves against the wrong Spring APIs.
cat > /root/app/pom.xml <<'XML'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>4.1.1</version>
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
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
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
      <version>0.1.0</version>
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
# spring-web is on the classpath only so the starter's web-filter bean signature
# resolves; we don't want an actual server (avoids port 8080 clashes between the
# check/solve runs), so run as a non-web app.
spring.main.web-application-type=none
PROPS

if [ "$LAB" = "resilient" ]; then
    # Full resilient app: an infinite transfer loop. main() blocks in run()
    # because the CommandLineRunner never returns, so the app keeps serving.
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
    # Skeleton: a bare app that starts and exits. It does NOT reference the
    # starter and prints no sentinel, so the Ch1 check (which greps for
    # CRDB_CONNECT_OK) fails until the learner adds a query runner.
    # main() uses SpringApplication.exit so `mvn spring-boot:run` returns
    # promptly instead of hanging the check.
    cat > /root/app/src/main/java/demo/App.java <<'JAVA'
package demo;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class App {
    public static void main(String[] args) {
        System.exit(SpringApplication.exit(SpringApplication.run(App.class, args)));
    }
    // TODO: add a runner that queries the database during the challenges.
}
JAVA
fi

mvn -q -f /root/app/pom.xml dependency:go-offline || true
echo "[INFO] Spring Boot lab assets ready (${LAB})"

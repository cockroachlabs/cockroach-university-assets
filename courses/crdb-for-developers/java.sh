#!/bin/bash
set -euxo pipefail

# Per-language setup for "CockroachDB for Java Developers" labs.
# Usage: java.sh [connect|resilient]
# Installs Temurin JDK 25 (the published core jar is Java 25 bytecode, so an
# older JDK can neither compile nor run against it) + Maven, then lays down a
# Maven project wired to the public CockroachDB Java library Pages Maven repo.

LAB=${1:-connect}
JDK_VER=${JDK_VER:-25}

# --- Install Maven, then Temurin JDK 25 as the system default ----------------
DEBIAN_FRONTEND=noninteractive apt -y install maven || true

# Install JDK 25 AFTER maven so our update-alternatives --set wins over the
# default-jre that maven pulls in. mvn (non-interactive check scripts) then
# resolves `java` -> JDK 25 off the PATH.
if ! java -version 2>&1 | grep -q 'version "25'; then
    curl -fsSL "https://api.adoptium.net/v3/binary/latest/${JDK_VER}/ga/linux/x64/jdk/hotspot/normal/eclipse" -o /tmp/jdk.tgz
    rm -rf "/opt/jdk-${JDK_VER}" && mkdir -p "/opt/jdk-${JDK_VER}"
    tar -C "/opt/jdk-${JDK_VER}" --strip-components=1 -xzf /tmp/jdk.tgz && rm -f /tmp/jdk.tgz
    update-alternatives --install /usr/bin/java  java  "/opt/jdk-${JDK_VER}/bin/java"  2500
    update-alternatives --install /usr/bin/javac javac "/opt/jdk-${JDK_VER}/bin/javac" 2500
    update-alternatives --set java  "/opt/jdk-${JDK_VER}/bin/java"
    update-alternatives --set javac "/opt/jdk-${JDK_VER}/bin/javac"
fi
export JAVA_HOME="/opt/jdk-${JDK_VER}"
grep -q 'JAVA_HOME=/opt/jdk' ~/.bashrc || echo "export JAVA_HOME=/opt/jdk-${JDK_VER}" >> ~/.bashrc

# Silence the JDK 25 "sun.misc.Unsafe::objectFieldOffset" deprecation warnings that
# Maven's bundled guava emits on every run. Harmless but noisy; this flag opts in.
export MAVEN_OPTS="${MAVEN_OPTS:-} --sun-misc-unsafe-memory-access=allow"
grep -q 'MAVEN_OPTS' ~/.bashrc || echo 'export MAVEN_OPTS="--sun-misc-unsafe-memory-access=allow"' >> ~/.bashrc

# --- CockroachDB Java library: public Pages Maven repo (anonymous, no token) --
mkdir -p /root/app/src/main/java && cd /root/app
cat > /root/app/pom.xml <<'XML'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>crdblab</artifactId>
  <version>1.0</version>
  <properties><maven.compiler.release>25</maven.compiler.release></properties>
  <repositories>
    <repository>
      <id>cockroachlabs</id>
      <url>https://cockroachlabs.github.io/cockroachdb-java-library/maven/</url>
    </repository>
  </repositories>
  <dependencies>
    <dependency>
      <groupId>com.cockroachlabs</groupId>
      <artifactId>cockroachdb-java-library-core</artifactId>
      <version>0.1.1</version>
    </dependency>
    <dependency>
      <groupId>org.postgresql</groupId>
      <artifactId>postgresql</artifactId>
      <version>42.7.3</version>
    </dependency>
  </dependencies>
  <build>
    <plugins>
      <!-- Ubuntu's Maven defaults to compiler-plugin 3.1, which predates the
           <release> option and falls back to source level 5. Pin a modern one. -->
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-compiler-plugin</artifactId>
        <version>3.13.0</version>
        <configuration><release>25</release></configuration>
      </plugin>
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
    # Seed the local repo cache so the first build is offline-fast.
    mvn -q -f /root/app/pom.xml dependency:go-offline || true
else
    # Skeleton: deliberately does NOT reference the library — the Ch1 check
    # greps for "Crdb", so the learner must add it. (No "Crdb" string here,
    # not even in a comment, or the check would pass for free.)
    cat > /root/app/src/main/java/App.java <<'JAVA'
import org.postgresql.ds.PGSimpleDataSource;

public class App {
    public static void main(String[] args) throws Exception {
        PGSimpleDataSource ds = new PGSimpleDataSource();
        ds.setUrl("jdbc:postgresql://localhost:26257/defaultdb?sslmode=disable&user=root");
        // TODO: run your first query during the challenges.
        System.out.println("starter app");
    }
}
JAVA
    mvn -q -f /root/app/pom.xml dependency:go-offline || true
fi

echo "[INFO] Java lab assets ready (${LAB})"

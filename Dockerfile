# --- Étape 1 : Construction (Build) ---
# On utilise une image Maven complète pour compiler le code
FROM maven:3.9.6-eclipse-temurin-17 AS build
WORKDIR /app

# On copie le pom.xml pour télécharger les dépendances (cache Docker)
COPY pom.xml .
RUN mvn dependency:go-offline

# On copie le code source et on génère le fichier .jar
COPY src ./src
RUN mvn clean package -DskipTests

# --- Étape 2 : Exécution (Run) ---
# On change pour une image JRE beaucoup plus légère (Debian-based)
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app

# On ne récupère que le résultat de la compilation (le .jar)
COPY --from=build /app/target/*.jar app.jar

# Port par défaut pour une application Spring Boot
EXPOSE 8080

# Commande pour démarrer l'application
ENTRYPOINT ["java", "-jar", "app.jar"]

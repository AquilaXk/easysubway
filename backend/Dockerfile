FROM eclipse-temurin:25-jre@sha256:d0eb1b9018b3044da1b7346f39e945f71095749853d69a3aa16b8c99dad9bb45

RUN groupadd --system --gid 10001 app && \
    useradd --uid 10001 --gid 10001 --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin app

WORKDIR /app

COPY --chown=10001:10001 build/libs/*.jar app.jar

EXPOSE 8080

ENV SPRING_PROFILES_ACTIVE=prod

USER 10001:10001

ENTRYPOINT ["java", "-jar", "/app/app.jar"]

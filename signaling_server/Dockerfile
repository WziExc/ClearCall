FROM dart:3.7-slim

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

COPY server.dart ./

EXPOSE 8080

CMD ["dart", "run", "server.dart", "--port=8080"]

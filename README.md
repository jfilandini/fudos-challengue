# Products API — Fudo Challenge

API JSON en Ruby, construida con Rack y Sinatra, sin Rails. Permite autenticarse,
solicitar la creación asíncrona de productos y consultar únicamente los recursos
del usuario autenticado. El contrato de la API se define en [openapi.yaml](openapi.yaml).

## Cómo levantar el proyecto

### Con Docker

Requisitos: Docker y Docker Compose. Desde la raíz del repositorio:

```bash
docker compose up --build
```

La API queda disponible en <http://localhost:9292>. Al iniciar, el contenedor
inicializa el esquema y ejecuta los seeds antes de levantar Puma. SQLite persiste
en `./data/production.sqlite3`, mediante el bind mount `./data:/data`, por lo que
los datos sobreviven a los reinicios. `data/` está excluido de la imagen Docker.

Para iniciar con datos de prueba:

```bash
SEED_MOCK_PRODUCTS=true docker compose up --build
```

| Usuario | Contraseña por defecto | Datos iniciales |
| --- | --- | --- |
| `admin` | `password123` | Sin productos de ejemplo |
| `testuser` | `password123` | 25 productos, solo con `SEED_MOCK_PRODUCTS=true` |

Ambos usuarios tienen los mismos permisos: `admin` es un nombre, no un rol especial.
Los seeds no borran datos ni cambian contraseñas existentes. Admin empieza vacío
solo en una base nueva. Los productos de ejemplo se insertan directamente, sin
crear jobs; repetir el seed conserva los existentes y repone los que falten.

`SEED_USERNAME` y `SEED_PASSWORD` permiten cambiar las credenciales iniciales.
Con datos de prueba habilitados, `SEED_USERNAME` debe ser distinto de `testuser`;
la contraseña configurada se usa para ambas cuentas nuevas.

### Sin Docker

Requisitos: Ruby 3.2.2 y Bundler.

```bash
bundle install
bundle exec rake db:setup db:seed
bundle exec puma -C config/puma.rb
```

Para agregar los datos de prueba localmente:

```bash
SEED_MOCK_PRODUCTS=true bundle exec rake db:seed
```

El entorno local usa `development` y guarda SQLite en `db/development.sqlite3`.
Docker usa `production`; Compose proporciona un secreto JWT de demostración.
Para un despliegue real, configurar un `JWT_SECRET` propio y credenciales adecuadas.
Fuera de Compose, iniciar con `RACK_ENV=production` requiere definir `JWT_SECRET`.

### Probar la API

```bash
bundle exec rspec
```

La suite cubre contratos HTTP, autenticación, aislamiento por usuario, idempotencia,
transacciones y workers concurrentes, incluyendo la interrupción de un proceso.
Los tests de demora usan un reloj controlado para evitar esperar cinco segundos.
La imagen Docker de ejecución no incluye las dependencias de tests.

También se puede importar [postman_collection.json](postman_collection.json).
La colección usa `testuser` por defecto: habilitar los datos de prueba y ejecutar
primero el login, que guarda el token. La creación guarda los identificadores del
job y del producto para las consultas siguientes.

## Funcionalidades y endpoints

| Método | Ruta | Autenticación | Función |
| --- | --- | --- | --- |
| POST | `/auth/login` | No | Obtener un JWT con usuario y contraseña |
| POST | `/products` | Bearer JWT | Solicitar una creación con `Idempotency-Key` |
| GET | `/products` | Bearer JWT | Listar los productos propios con paginación |
| GET | `/products/{id}` | Bearer JWT | Consultar un producto propio |
| GET | `/jobs/{id}` | Bearer JWT | Consultar el estado de una solicitud propia |
| GET | `/health` | No | Comprobar que la API responde |
| GET | `/openapi.yaml` | No | Descargar el contrato estático, sin caché |
| GET | `/AUTHORS` | No | Consultar la autoría, con caché por 24 horas |

El listado admite `page` (por defecto 1) y `per_page` (por defecto 20, máximo 100).
Devuelve `products` y `pagination`, con página, tamaño, total y cantidad de páginas.
Ordena por `created_at DESC, id DESC`; una página fuera de rango devuelve una lista
vacía. Nuevos productos pueden desplazar resultados entre consultas sucesivas.

## Arquitectura hexagonal

El proyecto separa las reglas de aplicación de HTTP y del almacenamiento.
Los casos de uso reciben sus dependencias por constructor; los contratos entre
objetos se expresan mediante métodos de Ruby, sin interfaces formales.

| Parte | Ubicación | Responsabilidad |
| --- | --- | --- |
| Dominio | `app/domain/` | Representar usuarios, productos y jobs |
| Casos de uso | `app/use_cases/` | Autenticar, encolar, procesar y consultar recursos |
| Adaptador HTTP | `app/api/` | Traducir requests y resultados a HTTP/JSON con Sinatra |
| Adaptador de persistencia | `app/persistence/` | Implementar repositorios y transacciones sobre SQLite |
| Adaptador de ejecución | `app/workers/` | Invocar periódicamente el procesamiento de jobs |
| Composición | `app/container.rb` | Construir y conectar las dependencias |

Por ejemplo, al recibir `POST /products`, `ProductsRoutes` llama a
`EnqueueProductCreation` con el nombre, el usuario autenticado y la clave de
idempotencia. El caso de uso programa el job mediante `JobRepository`, que lo
guarda en SQLite. La ruta convierte el resultado en una respuesta `202 Accepted`.

```text
HTTP → ProductsRoutes → EnqueueProductCreation → JobRepository → SQLite

ProductWorker → ProcessDueJobs → ProductRepository + JobRepository
                                      └─ transacción compartida ─┘
```

El caso de uso no construye respuestas HTTP ni ejecuta SQL. `Database` aporta la
conexión y actúa como unidad de trabajo: la inserción del producto y la finalización
del job se confirman juntas o se revierten juntas. Un `Monitor` coordina el acceso
a la conexión entre threads; los locks de SQLite coordinan procesos distintos.

## Capas de middleware

El stack se construye en [app/application.rb](app/application.rb), en este orden
de entrada. Las respuestas regresan en sentido inverso:

1. **`Rack::Deflater`**: comprime la respuesta cuando el cliente acepta gzip.
2. **`Rack::Static`**: sirve únicamente `/openapi.yaml` y `/AUTHORS`, sin pasar por
   Sinatra. El contrato lleva `no-store, no-cache, must-revalidate`; AUTHORS lleva
   `public, max-age=86400`. También soporta solicitudes `HEAD`.
3. **`Committee::Middleware::ResponseValidation`**: verifica las respuestas contra
   OpenAPI en desarrollo y tests. Está deshabilitado en producción.
4. **`Middleware::Authentication`**: valida el JWT en rutas protegidas y deja la
   identidad verificada en el entorno Rack. Rechaza solicitudes sin token válido
   antes de validar su payload.
5. **`Committee::Middleware::RequestValidation`**: valida las entradas contra
   OpenAPI antes de ejecutar las rutas. Permanece activo en producción.
6. **Rutas Sinatra**: invocan los casos de uso y producen las respuestas JSON.

Los archivos estáticos terminan su recorrido en `Rack::Static`; su respuesta sigue
pasando por el middleware exterior de compresión.

## Autenticación y aislamiento por usuario

`POST /auth/login` recibe `username` y `password`. Las contraseñas se almacenan como
hashes BCrypt. Si las credenciales son válidas, se emite un JWT firmado con HS256,
con una vigencia predeterminada de una hora.

El claim `sub` contiene el ID del usuario como texto, no su nombre. Para acceder a
productos o jobs, el cliente envía `Authorization: Bearer <token>`. El middleware
verifica la firma, la expiración y la presencia de un sujeto válido.

La identidad se obtiene del token verificado; el cliente no elige el propietario.
El job guarda `requested_by_user_id` y el worker lo copia al producto. Este campo
es interno: no se incluye en las respuestas y no se admite en el payload de creación.

Las consultas y los totales de paginación se filtran por ese ID. Consultar un
producto o job ajeno devuelve `404`, igual que uno inexistente. Los registros sin
propietario tampoco se exponen. Las respuestas que pasan la autenticación llevan
`Cache-Control: no-store`.

## Creación asíncrona e idempotencia

Una solicitud de creación tiene esta forma:

```http
POST /products
Authorization: Bearer <token>
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
Content-Type: application/json

{"name":"Café"}
```

La API persiste un job `pending`, programado para cinco segundos después, y responde
sin crear todavía el producto:

```http
HTTP/1.1 202 Accepted
Location: /jobs/<job_id>
Content-Type: application/json

{"job_id":"<job_id>","product_id":"<product_id>","status":"pending"}
```

El worker consulta cada 0,5 segundos y procesa hasta 100 jobs por pasada. Los cinco
segundos son la demora mínima: el polling y la carga pueden retrasar la disponibilidad.
Mientras no se complete el job, consultar el producto devuelve `404`.

La reserva de un job se realiza con un único `UPDATE ... RETURNING`: elige un
`pending` elegible y lo pasa a `in_progress` de forma atómica. Prioriza `run_at`,
`created_at` e `id`. Otro worker no puede reservar nuevamente ese mismo job pendiente.
La reserva se confirma antes de comenzar el procesamiento.

Luego, una transacción inserta el producto y marca el job como `completed`.
Si falla, se revierte la transacción y se intenta marcar el job como `failed`.
Con varios workers, el orden de reserva no garantiza el orden de finalización.
La aplicación inicia un worker por proceso; SQLite sigue serializando las escrituras.

### Reintentos de solicitudes

`Idempotency-Key` es obligatorio: admite entre 1 y 128 letras ASCII, números,
guiones o guiones bajos. Se genera una clave por creación y se reutiliza al reintentar.
Un índice único sobre `jobs(requested_by_user_id, idempotency_key)` evita duplicados
incluso ante solicitudes concurrentes.

| Solicitud | Resultado |
| --- | --- |
| Mismo usuario, clave y nombre exacto | Repite el `202`, los IDs y `Location` originales; no crea otro job |
| Mismo usuario y clave, distinto nombre | `409 idempotency_conflict` |
| Clave ausente o inválida | `400 invalid_request` |
| Otro usuario con la misma clave | Solicitud independiente |
| Nueva clave con el mismo nombre | Nueva creación permitida |

La respuesta repetida conserva `status: pending`, aunque el job ya haya terminado;
`GET /jobs/{id}` informa el estado actual. Reenviar una solicitud fallida no reintenta
su job. Las claves persisten con los jobs, sin expiración automática.

Si un proceso muere después de reservar un job, este puede quedar en `in_progress`.
Actualmente no hay recuperación ni reintentos automáticos. Antes de intervenir,
hay que confirmar que el worker original terminó; una fecha antigua no lo demuestra.

## Mejoras futuras

- **Active Record y migraciones:** evaluar Active Record como reemplazo del wrapper
  y los repositorios SQL para simplificar el mapeo y mantenimiento de persistencia.
  Es una alternativa de acceso a datos, no un reemplazo de SQLite. Mantener los
  casos de uso independientes del ORM y el índice único como garantía de idempotencia.
  Agregar migraciones versionadas cuando sea necesario evolucionar bases existentes.
  Hoy `db/schema.sql` define tablas e índices; el setup no migra esquemas antiguos.

- **Recuperación de jobs y claim tokens:** si se agregan leases, timeouts y
  reasignación, generar un token o una versión nueva en cada reserva. El worker debe
  presentar ese valor al completar o fallar el job, dentro de la transacción que
  crea el producto. Si perdió la reserva, la actualización debe fallar y revertir
  la inserción. Esto evita que un worker anterior, que se reanuda tarde, modifique
  el trabajo del nuevo propietario. El token no recupera jobs por sí mismo ni
  vuelve idempotentes los efectos externos; hoy no hace falta para impedir reservas
  duplicadas porque solo se reclaman jobs `pending` y no se reasignan los activos.

- **Ciclo de vida y configuración:** conectar el apagado de Puma con el del worker
  para detener nuevas reservas y terminar el trabajo activo dentro de un plazo.
  Validar rangos de configuración y rechazar secretos vacíos al iniciar.

- **Observabilidad:** incorporar logs estructurados, trazas y métricas, por ejemplo
  mediante New Relic. Vincular la solicitud HTTP con el job y medir latencia,
  errores, backlog, demora de ejecución y contención de la base. No registrar
  contraseñas ni tokens; no usar IDs individuales como etiquetas de métricas.

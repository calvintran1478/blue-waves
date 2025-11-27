# Getting Started

Install Crystal as per your operating system if it is not installed already: https://crystal-lang.org/install/.

In addition, ensure you have access to an S3-compatible storage provider along with a Postgres and Valkey database.

## Building Dependencies

cd into the src directory and run the following command to install the dependencies.
```bash
shards install
```

## Database Setup

These steps are for setting up Postgres and Valkey if you have them installed on your system. If you are using a hosted version you can skip this step.

Start Postgres if it not already running. On Linux this can be done using the command:
```bash
sudo systemctl start postgresql
```
Login to psql with the default user 'postgres'.
```bash
sudo -u postgres psql
```
Create a database for the server and give it a name.
```sql
postgres=# CREATE DATABASE <dbname>;
```
Create a user which can access and modify contents of the database. For this use the following commands with your own choice of username and password.
```sql
postgres=# CREATE USER <username> WITH ENCRYPTED PASSWORD '<password>';
postgres=# GRANT ALL PRIVILEGES ON DATABASE <dbname> TO <username>;
postgres=# \c <dbname>;
postgres=# GRANT ALL ON SCHEMA public TO <username>;
```
Next open the valkey.conf file in the src directory. Here you can change 'default', 'password', and '6379' to a username, password, and port of your choice. Alternatively, you can keep the default settings.

Start the Valkey database by running the following command in the src directory
```bash
valkey-server valkey.conf
```

## Setting up Environment Variables

In the src directory create a .env file with the following contents.
```
DB_CONN=<db_conn>

AUTH_DB_HOST=<auth_host>
AUTH_DB_USER=<auth_username>
AUTH_DB_PASSWORD=<auth_password>
AUTH_DB_PORT=<auth_port>
AUTH_TLS_ENABLED=<auth_tls>

MUSIC_DB_LOCATION=<music_location>
MUSIC_DB_KEY=<music_key>
MUSIC_DB_SCRET=<music_secret>
MUSIC_DB_ENDPOINT=<music_endpoint>
MUSIC_DB_BUCKET=<music_bucket>

API_SECRET=<api_secret>
BCRYPT_COST=<bcrypt_cost>
ACCESS_TOKEN_MINUTE_LIFESPAN=<access_token_lifespan>
REFRESH_TOKEN_HOUR_LIFESPAN=<refresh_token_lifespan>
```
DB_CONN should be a connection string to your Postgres instance. The AUTH_DB, and MUSIC_DB parameters should be those of your Valkey and S3-compatible storage provider, respectively. If you are running Postgres and Valkey locally, the host will be simply "localhost", the port for Postgres will be 5432, and the parameter AUTH_TLS_ENABLED should be set to "false". Your Postgres connection string should be of the form "postgres://<username>:<password>@localhost:5432/<dbname>" if it is being run locally.

The API secret should be a string only known by you (the one running the server), and is used for authentication purposes. If the server is made publicly available this should be sufficiently long and hard to guess (for example, a random string of 24 or more characters).

The bcrypt cost determines the cost of hashing user passwords. Larger values are more secure, but come with the tradeoff of slower logins. A standard default choice is 11, but this can be adjusted as needed.

The access token minute lifespan should be set to a small value (say 10-15 minutes). The refresh token lifespan can be set for much longer (e.g. 24 hours, or even a a few days).

The access token lifespan, refresh token lifespan, and bcrypt cost should all be positive integers.

## Rate Limiting

The rate_limit.conf file in the src directory defines how often certain endpoints can be accessed. Here the capacity, refill amount, and refill interval of an endpoint can be changed from their default values. The refill interval is expressed in seconds. Rate limiting is always done on a per-user basis.

## Database Table Setup

Before starting the server for the first time you will need to create the database tables. This can be done using the following command:
```bash
crystal setup.cr
```

## Starting the Server

You can start the server by running the following command in the src directory: 
```bash
crystal server.cr
```
Alternatively, you can compile the server ahead of time and start the server by running it as an executable.
```bash
crystal build server.cr
./server
```
If you want to optimize for performance, you can compile the server using the --release flag. However, compiling will take a bit longer.
```bash
crystal build --release server.cr
./server
```

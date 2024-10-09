# Getting Started

Install Crystal as per your operating system if it is not installed already: https://crystal-lang.org/install/.

In addition, ensure that Postgres is installed on your system.

## Building Dependencies

cd into the src directory and run the following command to install the dependencies.
```bash
shards install
```

## Database Setup

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

## Setting up Environment Variables

In the src directory create a .env file with the following contents.
```
DB_HOST=<host>
DB_USER=<username>
DB_PASSWORD=<password>
DB_PORT=<port>
DB_NAME=<dbname>
```
For the host and port you can simply put localhost and 5432, respectively. The database name, user, and password should match the same values you entered earlier when setting up your database.

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

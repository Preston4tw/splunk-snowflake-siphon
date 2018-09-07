# Splunk Snowflake Siphon

The Splunk Snowflake Siphon is a proof of concept of the use of Snowflake as a data lake for log data from which Splunk can siphon logs from.

Splunk Snowflake Siphon is built using the Splunk App [Splunk DB Connect](https://splunkbase.splunk.com/app/2686/) and the [Snowflake JDBC Driver](https://repo1.maven.org/maven2/net/snowflake/snowflake-jdbc/3.6.10/snowflake-jdbc-3.6.10.jar).

For testing I created a Dockerfile that's based on the official [Splunk Dockerfile](https://github.com/splunk/docker-splunk/blob/7.1.2/enterprise/Dockerfile) for Splunk 7.1.2.

## Installation

### Docker proof-of-concept

As a proof of concept, the Dockerfile in the repo when built and run provides a local instance of Splunk that comes with Splunk DB Connect, Oracle JRE 8, and the Snowflake JDBC driver pre-installed. 

1. git clone this repo
1. Download the Splunk DB Connect tarball from https://splunkbase.splunk.com/app/2686/ to the checkout of this repo
1. Run these commands
    ```sh
    # Generate a random password
    openssl rand -base64 6 > splunk_admin_pw.txt
    # Build the splunk container
    docker build -t snowflake_splunk .
    # Run a splunk instance
    docker run \
        -d \
        -e "SPLUNK_START_ARGS=--accept-license --seed-passwd $(cat splunk_admin_pw.txt)" \
        -e "SPLUNK_USER=root" \
        -p "8000:8000" snowflake_splunk
    ```

Once Splunk is up on https://localhost:8000, you can login as username: admin / password: splunk_admin_pw.txt. Then proceed to the [Configuration](#configuration) section.

### Installation to an existing Splunk Deployment

I will preface this section by saying I have very little actual experience with Splunk. Installation should be reasonably straight forward.

* Install a Java 8 runtime. Both OpenJDK and Oracle's JRE 8 should work. Splunk DB Connect requires this
* Install Splunk DB Connect
* Download the Snowflake JDBC driver to the drivers folder of the Splunk DB Connect app: /opt/splunk/etc/apps/splunk_app_db_connect/drivers/ in the Docker container by default.
* Patch in support for Snowflake JDBC as a connection type by adding the following lines to etc/apps/splunk_app_db_connect/default/db_connection_types.conf:
    ```ini
    [snowflake]
    displayName = Snowflake
    serviceClass = com.splunk.dbx2.DefaultDBX2JDBC
    jdbcUrlFormat = jdbc:snowflake://<host>/<database>
    jdbcDriverClass = net.snowflake.client.jdbc.SnowflakeDriver
    ```
* (Probably) Restart Splunk
* Proceed to the [Configuration](#configuration) section.

## Configuration

* Navigate to Apps -> Splunk DB Connect -> Configuration -> Identities
* Create an identity, which is a valid username/password combination for your Snowflake account. Splunk DB connect will use the credentials to connect to Snowflake. It is highly recommended this user has limited read-only permissions to your Snowflake account
* Navigate to Apps -> Splunk DB Connect -> Configuration -> Connections
* Create a connection to your Snowflake account. You will need to check the "Edit JDBC URL" box and specify a warehouse for the connection as a URL-style parameter. For example:
    ```text
    jdbc:snowflake://<account>/?warehouse=<warehouse>
    ```
* Navigate to Apps -> Splunk DB Connect -> Data Lab -> Inputs
* Create an input. An input is an arbitrary SQL statement, the result of which is ingested into Splunk.
* Enjoy the fruits of the labor of Splunk and Snowflake employees!

## FAQ

* Why did you copy the Splunk Dockerfile rather than using "FROM:splunk/splunk" in your Dockerfile?
  * The Splunk Dockerfile uses a volume for the directory where apps get installed: /opt/splunk/etc. Any modifications to a directory declared a volume during the build step are thrown away for the next build step, meaning that Splunk apps cannot be pre-installed in a Dockerfile descendent of the Splunk Dockerfile. Examination of the Dockerfile in this repo shows that the volume declaration of /opt/splunk/etc happens only after Splunk DB Connect is installed.
* How do you estimate the amount of data a query

## Known issues

* Specifying a database in the JDBC URL when creating a new database connection raises an error when saving the connection. Do not specify a database in the JDBC URL.
    ```text
    Database connection is invalid.
    No suitable driver found for jdbc:snowflake://<account>/<database>
    ```
* Snowflake timestamp columns don't work as rising columns for inputs. This doesn't work:
    ```sql
    SELECT * FROM "DATABASE"."SCHEMA"."TABLE"
    WHERE EVENT_TIME > ?
    order by EVENT_TIME asc
    ```
    Error:
    ```text
    java.lang.ClassCastException: java.lang.String cannot be cast to java.sql.Timestamp
    ```
    A workaround is to convert the timestamp to epoch format:
    ```sql
    SELECT
        date_part(epoch,event_time) AS epoch,
        *
    FROM "DATABASE"."SCHEMA"."TABLE"
    WHERE epoch > ?
    order by epoch asc
    ```

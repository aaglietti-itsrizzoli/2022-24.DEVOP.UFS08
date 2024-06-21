import os

from flask import Flask, jsonify
import psycopg2
from psycopg2 import sql

app = Flask(__name__)

# Database connection settings
# db_host = "34.135.197.119"
db_host = os.environ["DB1_HOST"]
db_port = "5432"
db_user = os.environ["DB1_USER1"]
db_password = os.environ["DB1_USER1_PSW"]
db_name="postgres"
@app.route('/databases', methods=['GET'])
def list_databases():
    try:
        # Connect to the PostgreSQL server
        connection = psycopg2.connect(
            host=db_host,
            port=db_port,
            user=db_user,
            password=db_password,
            dbname=db_name,
        )
        connection.autocommit = True
        
        # Create a cursor to perform database operations
        cursor = connection.cursor()
        
        # Execute the query to list databases
        cursor.execute("SELECT datname FROM pg_database WHERE datistemplate = false;")
        
        # Fetch all the databases
        databases = cursor.fetchall()
        
        # Close the cursor and connection
        cursor.close()
        connection.close()
        
        # Return the list of databases
        return jsonify([db[0] for db in databases])
    
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True)

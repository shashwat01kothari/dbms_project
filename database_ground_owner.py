import psycopg2
from logic import password1

def fetch_grounds(user_id):
    """
    Fetches all grounds created by a specific user (ground owner).
    """
    try:
        conn = psycopg2.connect(
            dbname="gorundbooking",
            user="postgres",
            password=password1,  # Replace with your actual password
            host="localhost",
            port="5432"
        )
        cursor = conn.cursor()
        query = """
        SELECT ground_id, ground_name, location, sport_type
        FROM grounds
        WHERE creator_id = %s
        """
        cursor.execute(query, (user_id,))
        result = cursor.fetchall()
        
        # Convert result to a list of dictionaries
        if result:
            grounds = [
                {
                    "ground_id": row[0],
                    "ground_name": row[1],
                    "location": row[2],
                    "sport_type": row[3]
                }
                for row in result
            ]
            return grounds
        else:
            return []
    except Exception as e:
        raise Exception(f"Error fetching grounds: {str(e)}")
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


from logic import password1

import psycopg2

def validate_user(email, password, user_type):
    try:
        # Connect to the PostgreSQL database
        conn = psycopg2.connect(
            dbname="gorundbooking",
            user="postgres",
            password=password1,  # Replace with actual password
            host="localhost",
            port=5432
        )
        
        cursor = conn.cursor()
        
        # Define the query to fetch user data
        query = """
            SELECT user_id, password  
            FROM users 
            WHERE email = %s AND user_type = %s;
        """
        
        # Execute the query with the provided parameters
        cursor.execute(query, (email, user_type))
        
        # Fetch the result
        result = cursor.fetchall()
        
        # If no result is returned, raise an exception
        if not result:
            raise Exception("User not found.")
        
        # Assuming plain text password for this example
        stored_password = result[0][1]  # Get the password from the query result
        if password != stored_password:
            raise Exception("Invalid password.")
        
        # Return the user_id
        return result[0][0]  # Return the user_id
        
    except Exception as e:
        raise Exception(f"Validation failed: {str(e)}")
    
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


import psycopg2

def get_grounds_by_location_and_sport(location, sport):
    """
    Retrieves grounds based on the provided location and/or sport.
    """
    try:
        # Establish a synchronous connection to the database
        conn = psycopg2.connect(
            dbname="gorundbooking",
            user="postgres",
            password=password1,  # Replace with actual password
            host="localhost",
            port=5432
        )
        cursor = conn.cursor()

        # Base query to fetch data from the grounds table
        query = """
            SELECT ground_id, ground_name, location, sport_type
            FROM grounds
            WHERE location = %s AND sport_type = %s
            ORDER BY priority ASC;
        """

        # Execute the query with placeholders replaced by the actual values
        cursor.execute(query, (location, sport))
        

        # Fetch the results
        result = cursor.fetchall()

        # Return the results as a list of dictionaries
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
        raise Exception(f"Failed to fetch grounds: {str(e)}")

    finally:
        # Close the cursor and the connection
        cursor.close()
        conn.close()

import psycopg2

def get_tournaments_by_location(location):
    """
    Fetch the list of all tournaments for a given location.
    
    Args:
        location (str): The location to filter tournaments.
    
    Returns:
        list: A list of dictionaries where each dictionary represents a tournament.
    """
    try:
        # Connect to the database
        conn = psycopg2.connect(
            dbname="gorundbooking",
            user="postgres",
            password=password1,  # Replace with your actual password variable
            host="localhost",
            port=5432
        )
        cursor = conn.cursor()

        # Query to fetch tournaments for the given location
        query = """
            SELECT tournament_id,tournament_name , location , sport_type, start_date, end_date 
            FROM tournaments 
            WHERE location = %s
        """
        cursor.execute(query, (location,))
        tournaments = cursor.fetchall()

        # Process results into a list of dictionaries
        tournament_list = [
            {    
                "tournament_id": row[0],
                "tournament_name": row[1],
                "location": row[2],
                "sport_type": row[3],
                "start_date": row[4],
                "end_date": row[5]
            }
            for row in tournaments
        ]

        return tournament_list

    except Exception as e:
        print(f"An error occurred: {e}")
        return []
    finally:
        cursor.close()
        conn.close()



def get_grounds_by_name(ground_name):
    """
    Retrieves grounds based on the provided ground_name.
    """
    try:
        # Establish a synchronous connection to the database
        conn = psycopg2.connect(
            dbname="gorundbooking",
            user="postgres",
            password=password1,  # Replace with actual password
            host="localhost",
            port=5432
        )
        cursor = conn.cursor()

        # Direct query to fetch grounds by ground_name
        query = """
        SELECT ground_id, ground_name, location, sport_type
        FROM grounds
        WHERE ground_name=%s
        LIMIT 5
        """

        # Execute the query with the provided ground_name
        cursor.execute(query, (ground_name,))

        # Fetch the results
        result = cursor.fetchall()

        # Return the results as a list of dictionaries
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
        raise Exception(f"Error occurred: {str(e)}")

    finally:
        # Close the cursor and the connection
        cursor.close()
        conn.close()

"""def check_and_book_ground(selected_date,selected_time:str,user_id:int,ground_id:int):
    try:

        # Connect to the database
        conn = psycopg2.connect(
            dbname="gorundbooking",
            user="postgres",
            password=password1,  
            host="localhost",
            port=5432
        )
        cursor = conn.cursor()

        # Call the check_and_book_ground function
        cursor.execute("""
"""          SELECT * 
            FROM check_and_book(
                p_user_id := %s, 
                p_ground_id := %s, 
                p_booking_date := %s, 
                p_time_slot := %s
            );"""
""", (user_id, ground_id, selected_date, selected_time))
        cursor.commit()
        # Fetch the result (booking_id, message)
        result = cursor.fetchone()
        
        if result:
            booking_id, message = result  # Unpack the result
            if booking_id:
                # Show success message if booking is successful
                return [booking_id, message]
            else:
                # Show error message if booking failed
                return None , message

    except Exception as e:
        # Handle any exception that occurs during the process
        raise Exception(f"Error occurred: {str(e)}")
    finally:
        # Close the cursor and the connection
        cursor.close()
        conn.close()
        """


def get_receipts(booking_id, user_id, ground_id):
    try:
        # Connect to the database
        conn = psycopg2.connect(
            dbname="gorundbooking",
            user="postgres",
            password=password1,  # Replace with actual password
            host="localhost",
            port=5432
        )
        cursor = conn.cursor()

        # Query to fetch receipt details where booking_id, user_id, and ground_id match
        query = """
        SELECT receipt_id, booking_id, user_id, ground_id, total_amount, issued_at
        FROM receipts
        WHERE booking_id = %s AND user_id = %s AND ground_id = %s;
        """
        
        # Execute the query with provided parameters
        cursor.execute(query, (booking_id, user_id, ground_id))
        
        # Fetch the result
        receipt = cursor.fetchone()  # Expecting a single receipt for the booking_id
        
        if receipt:
            # Return the receipt details as a dictionary for easier use
            receipt_details = {
                "receipt_id": receipt[0],
                "booking_id": receipt[1],
                "user_id": receipt[2],
                "ground_id": receipt[3],
                "total_amount": receipt[4],
                "issued_at": receipt[5]
            }
            return receipt_details
        else:
            return None  # If no matching receipt found
    
    except Exception as e:
        # Handle any exceptions that may occur
        print(f"Error occurred while fetching receipt: {e}")
        return None
    
    finally:
        # Close the cursor and connection
        cursor.close()
        conn.close()

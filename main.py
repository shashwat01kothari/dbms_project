from datetime import datetime
from tkinter import RIGHT, Frame, Text, ttk
import psycopg2
from tkcalendar import Calendar
import tkinter as tk
from tkinter import Tk, Label, Entry, Button, StringVar, OptionMenu, messagebox, Toplevel
from database_booking_user import  get_grounds_by_location_and_sport, get_grounds_by_name, get_receipts, get_tournaments_by_location, validate_user
from database_ground_owner import fetch_grounds  # Import your async validation function
from logic import password1


# Async helper for running asyncio tasks in Tkinter

def show_home_page(user_type, user_id):
    """
    Display the appropriate home page based on the user's type within the same main window.
    """
    home_window = Tk()
    home_window.title(f"{user_type.capitalize()} Home Page")
    home_window.attributes("-fullscreen", True)  # Enable full-screen mode
    home_window.configure(bg="#E3F2FD")  # Set background color

    # Allow exiting full-screen mode with Escape key
    home_window.bind("<Escape>", lambda event: home_window.attributes("-fullscreen", False))

    # Header
    header_frame = Frame(home_window, bg="#64B5F6", height=60)
    header_frame.pack(fill="x")
    Label(
        header_frame, text=f"Welcome, {user_type.capitalize()} id: {user_id}!", font=("Arial", 16, "bold"),
        bg="#64B5F6", fg="white"
    ).pack(pady=10)

    # Main Frame
    main_frame = Frame(home_window, bg="#E3F2FD", padx=20, pady=20)
    main_frame.pack(expand=True, fill="both")

    # Load the respective dashboard
    if user_type == "booking_user":
        create_booking_user_search(main_frame, user_id)
    elif user_type == "ground_owner":
        create_ground_owner_window(main_frame, user_id)
    elif user_type == "superadmin":
        create_super_admin_window(main_frame, user_id)

    # Footer
    footer_frame = Frame(home_window, bg="#E3F2FD")
    footer_frame.pack(fill="x")
    Button(
        footer_frame, text="Logout", font=("Arial", 12, "bold"), bg="red", fg="white",
        command=home_window.destroy
    ).pack(pady=10)

    home_window.mainloop()


def create_super_admin_window(main_frame, user_id):
    """
    Create the Super Admin Dashboard to cover the full page.
    """
    # Clear the main frame content
    for widget in main_frame.winfo_children():
        widget.destroy()

    # Configure the main frame
    main_frame.configure(bg="#E3F2FD")  # Background color
    main_frame.pack(fill="both", expand=True)  # Ensure it fills the entire window

    # Title Label
    Label(
        main_frame, text="Super Admin Dashboard", font=("Arial", 20, "bold"),
        bg="#E3F2FD", fg="#333333"
    ).pack(pady=30)

    # Button Frame for Actions
    button_frame = Frame(main_frame, bg="#E3F2FD")
    button_frame.pack(expand=True)  # Center in the middle of the screen

    Button(
        button_frame, text="Rewards", font=("Arial", 14, "bold"), bg="#64B5F6", fg="white",
        width=20, height=2, command=lambda: reward_users(user_id)
    ).pack(pady=20)

    Button(
        button_frame, text="Manage Promotions", font=("Arial", 14, "bold"), bg="#64B5F6", fg="white",
        width=20, height=2, command=lambda: manage_promotions(user_id)
    ).pack(pady=20)

    Button(
        button_frame, text="Create Tournaments", font=("Arial", 14, "bold"), bg="#64B5F6", fg="white",
        width=20, height=2, command=lambda: add_new_tournaments(user_id)
    ).pack(pady=20)

    Button(
        button_frame, text="LTV customers", font=("Arial", 14, "bold"), bg="#64B5F6", fg="white",
        width=20, height=2, command=lambda: get_total_credited_debited()
    ).pack(pady=20)

    # Footer with Close Button
    footer_frame = Frame(main_frame, bg="#E3F2FD")
    footer_frame.pack(fill="x", pady=20)

    Button(
        footer_frame, text="Close", font=("Arial", 12, "bold"), bg="red", fg="white",
        width=15, command=main_frame.quit
    ).pack(side="bottom", pady=10)


# Define placeholder functions for admin actions
def reward_users(admin_id):
    try:
        # Connect to your PostgreSQL database
        conn = psycopg2.connect(
            dbname="gorundbooking",
            user="postgres",
            password=password1,  # Replace with your actual password
            host="localhost",
            port=5432
        )
        cursor = conn.cursor()

        # Step 1: Find the top 10 users with the highest count in bookings and user_tournaments
        query = """
        SELECT user_id, COUNT(*) AS total_count
        FROM (
            SELECT user_id FROM bookings
            UNION ALL
            SELECT user_id FROM user_tournaments
        ) AS combined_data
        GROUP BY user_id
        ORDER BY total_count DESC
        LIMIT 10;
        """
        cursor.execute(query)
        top_users = cursor.fetchall()

        # Step 2: Update the wallet balance for each of the top 10 users by adding 50

        for users in top_users:
            user_id=users[0]
            cursor.execute("""
            UPDATE wallet
            SET balance = balance + 50
            WHERE wallet_id = %s;
            """, (user_id,))
            cursor.execute("""
            UPDATE wallet
            SET balance = balance - 50
            WHERE wallet_id = %s;
            """, (admin_id,))

        conn.commit()
        # Show success message
        messagebox.showinfo("Success", "Wallets updated successfully for top 10 users.")
        
    except Exception as e:
        # Rollback in case of an error
        conn.rollback()
        messagebox.showerror("Error", f"An error occurred: {e}")

    finally:
        # Close the cursor and connection
        cursor.close()
        conn.close()


def manage_promotions(admin_id):
    try:
        # Establish the database connection
        connection = psycopg2.connect(
            dbname="gorundbooking",
            user="postgres",
            password=password1,  
            host="localhost",
            port=5432
        )
        cursor = connection.cursor()

        # Start a transaction (disable autocommit)
        connection.autocommit = False

        # Step 1: Get all users who have promotions with status 'Pending'
        cursor.execute("""
            SELECT DISTINCT creator_id
            FROM promotions
            WHERE status = 'Pending'
        """)
        users = cursor.fetchall()

        # Step 2: Loop over each user and deduct balance for each pending promotion
        for user in users:
            user_id = user[0]

            # Get all pending promotions for this user
            cursor.execute("""
                SELECT ground_id
                FROM promotions
                WHERE creator_id = %s AND status = 'Pending'
            """, (user_id,))
            pending_promotions = cursor.fetchall()

            cursor.execute("""
                UPDATE promotions
                SET status = 'Approved'
                WHERE creator_id = %s AND status = 'Pending' ;
            """, (user_id,))

            # Step 3: For each pending promotion, deduct 100 from the user's wallet
            for promotion in pending_promotions:
                ground_id = promotion[0]

                # Update the user's wallet balance (deduct 100 for each pending promotion)
                cursor.execute("""
                    UPDATE wallet
                    SET balance = balance - 100
                    WHERE user_id = %s
                    RETURNING wallet_id
                """, (user_id,))

                # Fetch wallet_id after update
                wallet_id = cursor.fetchone()[0]

                # Step 4: Insert a record in the wallet_transactions table
                cursor.execute("""
                    INSERT INTO wallet_transactions (wallet_id, transaction_type, amount, description)
                    VALUES (%s, 'debit', 100, 'Deducted for pending promotion')
                """, (wallet_id,))

                cursor.execute("""
                    UPDATE wallet
                    SET balance = balance + 100
                    WHERE user_id = %s
                """, (admin_id,))

                # Step 5: Deduct the priority of the corresponding ground by 1
                cursor.execute("""
                    UPDATE grounds
                    SET priority = priority - 1
                    WHERE ground_id = %s
                """, (ground_id,))

        # Commit the transaction to save all changes
        connection.commit()

        # Close cursor and connection
        cursor.close()
        connection.close()

        # Show success message
        messagebox.showinfo("Promotions Updated", "Wallet balances updated, transactions logged, and priorities updated for all pending promotions.")

    except Exception as e:
        # Rollback transaction in case of error
        if connection:
            connection.rollback()

        # Show error message
        messagebox.showerror("Error", f"An error occurred: {str(e)}")

    finally:
        # Ensure that the connection is always closed
        if connection:
            connection.close()



def add_new_tournaments(user_id):
    def submit_tournament():
        # Fetch user inputs
        tournament_name = name_entry.get()
        sport_type = sport_entry.get()
        location = location_entry.get()
        start_date = start_date_entry.get()
        end_date = end_date_entry.get()

        # Ensure no fields are left empty
        if not all([tournament_name, sport_type, location, start_date, end_date]):
            messagebox.showerror("Error", "Please fill in all the fields.")
            return

        try:
            # Database connection
            conn = psycopg2.connect(
                dbname="gorundbooking",
                user="postgres",
                password=password1,  # Replace with your password variable
                host="localhost",
                port=5432
            )
            cursor = conn.cursor()

            # Insert query
            query = """
                INSERT INTO tournaments (tournament_name, sport_type, location, start_date, end_date, created_at)
                VALUES (%s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
            """
            cursor.execute(
                query,
                (tournament_name, sport_type, location, start_date, end_date)
            )
            conn.commit()

            messagebox.showinfo(
                "Success",
                f"Tournament '{tournament_name}' has been added successfully!"
            )

            # Clear the fields after successful insertion
            name_entry.delete(0, tk.END)
            sport_entry.delete(0, tk.END)
            location_entry.delete(0, tk.END)
            start_date_entry.delete(0, tk.END)
            end_date_entry.delete(0, tk.END)

        except Exception as e:
            messagebox.showerror("Error", f"An error occurred: {e}")
        finally:
            cursor.close()
            conn.close()

    # Create a top-level window
    top_window = tk.Toplevel()
    top_window.title("Add New Tournament")
    top_window.attributes("-fullscreen", True)  # Enable fullscreen mode
    top_window.configure(bg="#E3F2FD")  # Background color

    # Allow exiting fullscreen mode with Escape key
    top_window.bind("<Escape>", lambda event: top_window.attributes("-fullscreen", False))

    # Title Label
    tk.Label(
        top_window, text="Add New Tournament", font=("Arial", 24, "bold"),
        bg="#E3F2FD", fg="#333333"
    ).pack(pady=30)

    # Form Frame
    form_frame = tk.Frame(top_window, bg="#E3F2FD")
    form_frame.pack(pady=20)

    # Labels and Entry Fields
    tk.Label(form_frame, text="Tournament Name:", font=("Arial", 16), bg="#E3F2FD").grid(row=0, column=0, sticky="e", pady=10, padx=10)
    name_entry = tk.Entry(form_frame, font=("Arial", 16), width=30)
    name_entry.grid(row=0, column=1, pady=10)

    tk.Label(form_frame, text="Sport Type:", font=("Arial", 16), bg="#E3F2FD").grid(row=1, column=0, sticky="e", pady=10, padx=10)
    sport_entry = tk.Entry(form_frame, font=("Arial", 16), width=30)
    sport_entry.grid(row=1, column=1, pady=10)

    tk.Label(form_frame, text="Location:", font=("Arial", 16), bg="#E3F2FD").grid(row=2, column=0, sticky="e", pady=10, padx=10)
    location_entry = tk.Entry(form_frame, font=("Arial", 16), width=30)
    location_entry.grid(row=2, column=1, pady=10)

    tk.Label(form_frame, text="Start Date (YYYY-MM-DD):", font=("Arial", 16), bg="#E3F2FD").grid(row=3, column=0, sticky="e", pady=10, padx=10)
    start_date_entry = tk.Entry(form_frame, font=("Arial", 16), width=30)
    start_date_entry.grid(row=3, column=1, pady=10)

    tk.Label(form_frame, text="End Date (YYYY-MM-DD):", font=("Arial", 16), bg="#E3F2FD").grid(row=4, column=0, sticky="e", pady=10, padx=10)
    end_date_entry = tk.Entry(form_frame, font=("Arial", 16), width=30)
    end_date_entry.grid(row=4, column=1, pady=10)

    # Button Frame
    button_frame = tk.Frame(top_window, bg="#E3F2FD")
    button_frame.pack(pady=30)

    # Submit Button
    submit_button = tk.Button(
        button_frame, text="Add Tournament", font=("Arial", 16, "bold"),
        bg="#64B5F6", fg="white", width=15, command=submit_tournament
    )
    submit_button.pack(side="left", padx=20)

    # Close Button
    close_button = tk.Button(
        button_frame, text="Close", font=("Arial", 16, "bold"),
        bg="red", fg="white", width=10, command=top_window.destroy
    )
    close_button.pack(side="right", padx=20)

def get_total_credited_debited():
    try:
        # Connect to your PostgreSQL database
        conn = psycopg2.connect(
            dbname="gorundbooking",  # Replace with your actual database name
            user="postgres",  # Replace with your actual username
            password=password1,  # Replace with your actual password
            host="localhost",
            port=5432
        )
        cursor = conn.cursor()

        # Query to find total debited and credited amounts for users with user_type = 'booking_user', limited to 10 users
        query = """
        SELECT 
            u.user_id,
            COALESCE(SUM(CASE WHEN wt.transaction_type = 'credit' THEN wt.amount ELSE 0 END), 0) AS total_credited,
            COALESCE(SUM(CASE WHEN wt.transaction_type = 'debit' THEN wt.amount ELSE 0 END), 0) AS total_debited
        FROM 
            users u
        LEFT JOIN 
            wallet_transactions wt ON u.user_id = wt.wallet_id
        WHERE 
            u.user_type = 'booking_user'
        GROUP BY 
            u.user_id
        ORDER BY 
            total_credited DESC, total_debited DESC
        LIMIT 10;
        """

        # Execute the query
        cursor.execute(query)
        result = cursor.fetchall()

        # Create a new Toplevel window
        top_window = tk.Toplevel()
        top_window.title("Top 10 Users - Debited and Credited Amounts")

        # Add a text widget to the Toplevel window to display the results
        text_widget = tk.Text(top_window, width=80, height=20)
        text_widget.pack(padx=10, pady=10)

        # Insert the results into the text widget
        text_widget.insert(tk.END, "User ID | Total Credited | Total Debited\n")
        text_widget.insert(tk.END, "-" * 50 + "\n")

        for row in result:
            user_id, total_credited, total_debited = row
            text_widget.insert(tk.END, f"{user_id} | {total_credited} | {total_debited}\n")

        # Disable editing in the text widget
        text_widget.config(state=tk.DISABLED)

    except Exception as e:
        messagebox.showerror("Error", f"An error occurred: {e}")

    finally:
        # Close the cursor and connection
        cursor.close()
        conn.close()


def create_ground_owner_window(main_frame, user_id):
    """
    Function for ground owner to view and manage their grounds.
    """
    # Clear the main frame
    for widget in main_frame.winfo_children():
        widget.destroy()

    # Fetch the grounds owned by the user
    result = fetch_grounds(user_id)

    # Display the grounds
    if not result:
        Label(main_frame, text="No grounds found under your ownership.", font=("Arial", 14), bg="#E3F2FD", fg="red").pack(pady=20)
    else:
        for ground in result:
            ground_frame = Frame(main_frame, bg="#FFFFFF", padx=10, pady=10, relief="solid", borderwidth=1)
            ground_frame.pack(fill="x", pady=5)

            ground_info = f"ID: {ground['ground_id']} | Name: {ground['ground_name']} | Location: {ground['location']} | Sport: {ground['sport_type']}"
            Label(ground_frame, text=ground_info, font=("Arial", 12), bg="#FFFFFF").pack(side="left", fill="x", expand=True)

            Button(
                ground_frame,
                text="Manage",
                font=("Arial", 10, "bold"),
                bg="#64B5F6",
                fg="white",
                command=lambda g=ground: edit_ground_details(g, user_id)
            ).pack(side="right", padx=10)

            Button(
                ground_frame,
                text="Promote",
                font=("Arial", 10, "bold"),
                bg="#64B5F6",
                fg="white",
                command=lambda g=ground: promote_ground(g, user_id)
            ).pack(side="right", padx=10)


def promote_ground(ground,user_id):
        """Promote the selected ground by adding it to the promotions table."""
        try:
            conn = psycopg2.connect(
                dbname="gorundbooking",
                user="postgres",
                password=password1,  
                host="localhost",
                port=5432
            )
            cursor = conn.cursor()

            # Insert the ground into the promotions table
            query = """
                INSERT INTO promotions (ground_id, creator_id, status, details)
                VALUES (%s, %s, %s, %s)
            """
            cursor.execute(query, (ground['ground_id'], user_id, 'Pending', f"Promotion for {ground['ground_name']}"))
            conn.commit()

            messagebox.showinfo("Success", f"Ground '{ground['ground_name']}' has been promoted successfully!")
        except Exception as e:
            messagebox.showerror("Error", f"An error occurred: {e}")
        finally:
            cursor.close()
            conn.close()

def edit_ground_details(ground, user_id):
    """
    Open a window to edit and update ground details.
    """  # Close the previous window
    edit_window = Toplevel()
    edit_window.title(f"Edit {ground['ground_name']}")
    edit_window.configure(bg="#E3F2FD")
    # Make the window fullscreen
    edit_window.geometry(f"{edit_window.winfo_screenwidth()}x{edit_window.winfo_screenheight()}+0+0")

    # Edit Fields
    Label(edit_window, text="Edit Ground Name:", font=("Arial", 12), bg="#E3F2FD").pack(pady=5)
    ground_name_entry = Entry(edit_window, font=("Arial", 12), width=30)
    ground_name_entry.insert(0, ground['ground_name'])
    ground_name_entry.pack(pady=5)

    Label(edit_window, text="Edit Location:", font=("Arial", 12), bg="#E3F2FD").pack(pady=5)
    location_entry = Entry(edit_window, font=("Arial", 12), width=30)
    location_entry.insert(0, ground['location'])
    location_entry.pack(pady=5)

    Label(edit_window, text="Edit Sport Type:", font=("Arial", 12), bg="#E3F2FD").pack(pady=5)
    sport_entry = Entry(edit_window, font=("Arial", 12), width=30)
    sport_entry.insert(0, ground['sport_type'])
    sport_entry.pack(pady=5)

    # Save Changes Function
    def save_changes():
        new_name = ground_name_entry.get()
        new_location = location_entry.get()
        new_sport = sport_entry.get()

        if not new_name or not new_location or not new_sport:
            messagebox.showerror("Error", "All fields must be filled!")
            return

        conn = None  # Initialize the connection
        cursor = None  # Initialize the cursor
        try:
            conn = psycopg2.connect(
                dbname="gorundbooking",
                user="postgres",
                password=password1,  # Replace with your password
                host="localhost",
                port=5432
            )
            cursor = conn.cursor()

            # Update query
            update_query = """
                UPDATE grounds
                SET ground_name = %s, location = %s, sport_type = %s
                WHERE ground_id = %s AND creator_id = %s
            """
            cursor.execute(update_query, (new_name, new_location, new_sport, ground['ground_id'], user_id))
            conn.commit()

            # Success Message
            messagebox.showinfo("Success", f"Ground '{new_name}' updated successfully!")
            edit_window.destroy()

        except Exception as e:
            if conn:
                conn.rollback()  # Rollback changes in case of error
            messagebox.showerror("Error", f"Failed to update ground: {e}")

        finally:
            # Close cursor and connection if they were successfully initialized
            if cursor:
                cursor.close()
            if conn:
                conn.close()

    # Save and Close Buttons
    button_frame = Frame(edit_window, bg="#E3F2FD")
    button_frame.pack(pady=20)

    Button(
        button_frame, text="Save Changes", font=("Arial", 12, "bold"), bg="#64B5F6", fg="white",
        width=15, command=save_changes
    ).pack(side="left", padx=10)

    Button(
        button_frame, text="View Bookings", font=("Arial", 12, "bold"), bg="#64B5F6", fg="white",
        width=15, command=lambda: view_bookings(ground)
    ).pack(side="left", padx=10)

    Button(
        button_frame, text="Close", font=("Arial", 12, "bold"), bg="red", fg="white",
        width=10, command=edit_window.destroy
    ).pack(side="right", padx=10)
    

def view_bookings(ground):
    """
    View all bookings for the given ground.
    """
    try:
        conn = psycopg2.connect(
            dbname="gorundbooking",
            user="postgres",
            password=password1,  # Replace with your password
            host="localhost",
            port=5432
        )
        cursor = conn.cursor()

        # Fetch bookings for the ground
        booking_query = """
        SELECT booking_id, user_id, booking_timestamp
        FROM bookings
        WHERE ground_id = %s
        """
        cursor.execute(booking_query, (ground['ground_id'],))
        bookings = cursor.fetchall()

        # Create the bookings window
        booking_window = tk.Toplevel()
        booking_window.title(f"Bookings for {ground['ground_name']}")
        booking_window.configure(bg="#E3F2FD")
        # Make the window fullscreen
        booking_window.geometry(f"{booking_window.winfo_screenwidth()}x{booking_window.winfo_screenheight()}+0+0")

        # Frame for bookings
        bookings_frame = tk.Frame(booking_window, bg="#FFFFFF", padx=15, pady=15)
        bookings_frame.pack(padx=20, pady=20, fill="both", expand=True)

        if not bookings:
            Label(bookings_frame, text="No bookings found.", font=("Arial", 12), bg="#FFFFFF", fg="red").pack(pady=10)
        else:
            for booking in bookings:
                booking_info = (
                    f"Booking ID: {booking[0]} | User ID: {booking[1]} | Time: {booking[2]}"
                )
                Label(bookings_frame, text=booking_info, font=("Arial", 12), bg="#FFFFFF").pack(pady=5)

        # Close Button
        tk.Button(
            booking_window, text="Close", font=("Arial", 12, "bold"), bg="red", fg="white",
            width=15, command=booking_window.destroy
        ).pack(pady=20)

    except Exception as e:
        messagebox.showerror("Error", f"Error fetching bookings: {e}")

    finally:
        if conn:
            cursor.close()
            conn.close()



def create_booking_user_search(main_frame, user_id):
    """
    Create the search interface for booking users, using the same theme as the login page.
    """
    # Search for a Ground Section
    ground_frame = Frame(main_frame, bg="#FFFFFF", padx=15, pady=15, relief="solid", borderwidth=1)
    ground_frame.pack(pady=20, fill="x")

    Label(ground_frame, text="Search for a Ground", font=("Arial", 14, "bold"), bg="#FFFFFF").grid(row=0, column=0, columnspan=2, pady=10)

    Label(ground_frame, text="Ground Name:", font=("Arial", 12), bg="#FFFFFF").grid(row=1, column=0, sticky="w", pady=5)
    ground_search_entry = Entry(ground_frame, font=("Arial", 12), width=30)
    ground_search_entry.grid(row=1, column=1, pady=5)

    Label(ground_frame, text="Location:", font=("Arial", 12), bg="#FFFFFF").grid(row=2, column=0, sticky="w", pady=5)
    location_var = StringVar()
    location_var.set("Select Location")
    location_menu = OptionMenu(ground_frame, location_var, "Indirangar", "Koramangala", "Banashankari")
    location_menu.config(font=("Arial", 12), width=20)
    location_menu.grid(row=2, column=1, pady=5)

    Label(ground_frame, text="Sport Type:", font=("Arial", 12), bg="#FFFFFF").grid(row=3, column=0, sticky="w", pady=5)
    sport_var = StringVar()
    sport_var.set("Select Sport")
    sport_menu = OptionMenu(ground_frame, sport_var, "Football", "Cricket", "Badminton")
    sport_menu.config(font=("Arial", 12), width=20)
    sport_menu.grid(row=3, column=1, pady=5)

    search_button = Button(
        ground_frame,
        text="Search Ground",
        font=("Arial", 12, "bold"),
        bg="#64B5F6",
        fg="white",
        command=lambda: (
            search_based_filter(location_var.get(), sport_var.get(), user_id)
            if not ground_search_entry.get()
            else search_based_name(ground_search_entry.get(), user_id)
        ),
    )
    search_button.grid(row=4, column=0, columnspan=2, pady=10)

    # View Tournaments Section
    tournament_frame = Frame(main_frame, bg="#FFFFFF", padx=15, pady=15, relief="solid", borderwidth=1)
    tournament_frame.pack(pady=20, fill="x")

    Label(tournament_frame, text="View Tournaments", font=("Arial", 14, "bold"), bg="#FFFFFF").grid(row=0, column=0, columnspan=2, pady=10)

    Label(tournament_frame, text="Location:", font=("Arial", 12), bg="#FFFFFF").grid(row=1, column=0, sticky="w", pady=5)
    tournament_location_var = StringVar()
    tournament_location_var.set("Select Location")
    tournament_location_menu = OptionMenu(tournament_frame, tournament_location_var, "Indirangar", "Koramangala", "Banashankari")
    tournament_location_menu.config(font=("Arial", 12), width=20)
    tournament_location_menu.grid(row=1, column=1, pady=5)

    view_button = Button(
        tournament_frame,
        text="View Tournaments",
        font=("Arial", 12, "bold"),
        bg="#64B5F6",
        fg="white",
        command=lambda: display_tournaments(user_id, tournament_location_var.get())
        if tournament_location_var.get() != "Select Location"
        else messagebox.showinfo("Input Error", "Please select a location."),
    )
    view_button.grid(row=2, column=0, columnspan=2, pady=10)

    profile_frame = Frame(main_frame, bg="#FFFFFF", padx=15, pady=15, relief="solid", borderwidth=1)
    profile_frame.pack(pady=20, fill="x")
    add_money_button = Button(
        profile_frame,
        text="Add Money",
        font=("Arial", 12, "bold"),
        bg="#4CAF50",
        fg="white",
        command=lambda: add_money(user_id)  # Replace `add_money` with your actual function to add money
    )
    add_money_button.grid(row=1, column=1, columnspan=2, pady=10)
    view_booking_button = Button(
        profile_frame,
        text="View bookings",
        font=("Arial", 12, "bold"),
        bg="#4CAF50",
        fg="white",
        command=lambda: display_booking_and_receipt_window(user_id)  # Replace `add_money` with your actual function to add money
    )
    view_booking_button.grid(row=1, column=5, columnspan=2, pady=10)

    issues_frame = Frame(main_frame, bg="#FFFFFF", padx=15, pady=15, relief="solid", borderwidth=1)
    issues_frame.pack(pady=20, fill="x")
    Label(issues_frame, text="Report Issues", font=("Arial", 14, "bold"), bg="#FFFFFF").grid(row=0, column=0, columnspan=2, pady=10)
    issue_text_box = Text(issues_frame, width=50, height=5, font=("Arial", 12))
    issue_text_box.grid(row=0, column=1, columnspan=2, pady=10)

    # Submit Button
    submit_issue_button = Button(
        issues_frame,
        text="Submit Issue",
        font=("Arial", 12, "bold"),
        bg="#FF5722",
        fg="white",
        command=lambda: submit_issue(user_id,issue_text_box.get("1.0", "end-1c"))  # Extracting text from the text box
    )
    submit_issue_button.grid(row=0, column=5, columnspan=2, pady=10)

def view_user_bookings(user_id):
    try:
        # Connect to your PostgreSQL database
        conn = psycopg2.connect(
            dbname="gorundbooking",
            user="postgres",
            password=password1,  # Replace with your actual password
            host="localhost",
            port=5432
        )
        cursor = conn.cursor()

        # SQL query to join booking and receipt details based on booking_id and receipt_id

        # Execute the query
        cursor.execute("""
        SELECT 
            b.booking_id,
            b.user_id AS booking_user_id,
            b.ground_id,
            b.booking_date,
            b.time_slot,
            r.receipt_id,
            r.total_amount,
            r.issued_at
        FROM 
            bookings b
        JOIN 
            receipts r ON b.booking_id = r.booking_id
        WHERE 
            b.user_id = %s;
        """, (user_id,))

        # Fetch the result
        result = cursor.fetchone()
        print(result)
        if result:
            # Format the result for display
            booking_details = {
                'booking_id': result[0],
                'user_id': result[1],
                'ground_id': result[2],
                'booking_date': result[3],
                'time_slot': result[4],
                'receipt_id': result[5],
                'total_amount': result[6],
                'issued_at': result[7]
            }

            return booking_details  # Return the details as a dictionary

        else:
            messagebox.showerror("Error", "No booking or receipt found for the provided IDs.")
            return None

    except Exception as e:
        messagebox.showerror("Error", f"An error occurred: {e}")
        return None

    finally:
        # Close the database connection
        cursor.close()
        conn.close()

def display_booking_and_receipt_window(user_id):
    details = view_user_bookings(user_id)

    if details:
        # Create a new top-level window
        top_window = tk.Toplevel()
        top_window.title("Booking and Receipt Details")

        # Display the details in a formatted manner using labels
        labels = [
            f"Booking ID: {details['booking_id']}",
            f"User ID: {details['user_id']}",
            f"Ground ID: {details['ground_id']}",
            f"Booking Date: {details['booking_date']}",
            f"Time Slot: {details['time_slot']}",
            f"Receipt ID: {details['receipt_id']}",
            f"Total Amount: {details['total_amount']}",
            f"Issued At: {details['issued_at']}"
        ]
        print(labels)
        # Pack each label with some padding
        for label_text in labels:
            label = tk.Label(top_window, text=label_text, font=("Arial", 12))
            label.pack(pady=5)

        # Add a Close button to close the window
        close_button = tk.Button(top_window, text="Close", command=top_window.destroy)
        close_button.pack(pady=10)
        
        # Make sure the window is properly sized
        top_window.geometry("400x300")
    else:
        messagebox.showerror("Error", "No details found to display.")

def submit_issue(user_id,issue_text):
    """
    Handle the submission of an issue by inserting it into the PostgreSQL database.
    """
    if not issue_text.strip():
        messagebox.showwarning("Input Error", "Please describe the issue before submitting.")
        return

    try:
        # Connect to the PostgreSQL database
        connection = psycopg2.connect(
            dbname="gorundbooking",
            user="postgres",
            password=password1,  # Replace with your actual password
            host="localhost",
            port=5432
                          # Replace with your port if different
        )
        cursor = connection.cursor()

        # Insert the issue into the table
        cursor.execute(
            """
            INSERT INTO user_issues (user_id, description)
            VALUES (%s, %s)
            """,
            (user_id, issue_text.strip())
        )
        # Commit the transaction
        connection.commit()

        # Inform the user of success
        messagebox.showinfo("Success", "Your issue has been submitted. Thank you!")

    except psycopg2.Error as e:
        # Rollback in case of error
        if connection:
            connection.rollback()
        messagebox.showerror("Database Error", f"An error occurred: {e}")
    finally:
        # Close the database connection
        if cursor:
            cursor.close()
        if connection:
            connection.close()


def add_money(user_id):
    try:
        # Connect to the database
        conn = psycopg2.connect(
            dbname="gorundbooking",
            user="postgres",
            password=password1,  # Replace with your actual password
            host="localhost",
            port=5432
        
        )
        cursor = conn.cursor()

        # Begin a transaction
        conn.autocommit = False

        # Fetch the user's wallet ID and current balance
        cursor.execute(
            """
            SELECT wallet_id, balance
            FROM wallet
            WHERE user_id = %s
            FOR UPDATE;
            """,
            (user_id,)
        )
        wallet = cursor.fetchone()
        if not wallet:
            raise ValueError("Wallet not found for the given user_id.")

        wallet_id, current_balance = wallet

        # Update the user's balance
        new_balance = current_balance + 100
        cursor.execute(
            """
            UPDATE wallet
            SET balance = %s
            WHERE wallet_id = %s;
            """,
            (new_balance, wallet_id)
        )

        # Insert a record into wallet_transactions
        cursor.execute(
            """
            INSERT INTO wallet_transactions (wallet_id, transaction_type, amount, description)
            VALUES (%s, %s, %s, %s);
            """,
            (wallet_id, 'credit', 100, 'Added money to wallet.')
        )

        # Commit the transaction
        conn.commit()

        # Show success message
        messagebox.showinfo("Success", "Rs.100 added successfully!")
    except Exception as e:
        # Rollback in case of error
        if conn:
            conn.rollback()
        # Show error message
        messagebox.showerror("Error", f"An error occurred: {e}")
    finally:
        # Close the cursor and connection
        if cursor:
            cursor.close()
        if conn:
            conn.close()

    

def join_tournament(user_id, tournament_id):
    """Insert a record into the user_tournaments table."""
    try:
        conn = psycopg2.connect(
            dbname="gorundbooking",
            user="postgres",
            password=password1,  # Replace with your database password
            host="localhost",
            port=5432
        )
        cursor = conn.cursor()

        query = """
            INSERT INTO user_tournaments (user_id, tournament_id, joined_at)
            VALUES (%s, %s, CURRENT_TIMESTAMP)
        """
        cursor.execute(query, (user_id, tournament_id))
        conn.commit()

        messagebox.showinfo("Success", "You have successfully joined the tournament!")
    except psycopg2.IntegrityError:
        conn.rollback()
        messagebox.showerror("Error", "You are already registered for this tournament.")
    except Exception as e:
        messagebox.showerror("Error", f"An error occurred: {e}")
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

def display_tournaments(user_id, location):
    """
    Displays a list of tournaments based on the location with an option to join.
    """
    result = get_tournaments_by_location(location)
    
    # Create the window
    result_window = tk.Toplevel()
    result_window.title("Tournaments")
    result_window.configure(bg="#E3F2FD")  # Background color

    # Header
    header_frame = Frame(result_window, bg="#64B5F6", height=50)
    header_frame.pack(fill="x")
    Label(header_frame, text="Tournaments", font=("Arial", 16, "bold"), bg="#64B5F6", fg="white").pack(pady=10)

    # Main Frame for Results
    main_frame = Frame(result_window, bg="#E3F2FD", padx=15, pady=15)
    main_frame.pack(fill="both", expand=True)

    # Create a scrollable canvas
    canvas = tk.Canvas(main_frame, bg="#E3F2FD", highlightthickness=0)
    scrollbar = tk.Scrollbar(main_frame, orient="vertical", command=canvas.yview)
    scrollable_frame = Frame(canvas, bg="#FFFFFF", padx=10, pady=10)

    # Configure canvas and scrollbar
    canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
    canvas.configure(yscrollcommand=scrollbar.set)
    canvas.pack(side="left", fill="both", expand=True)
    scrollbar.pack(side="right", fill="y")

    # Populate tournaments
    if not result:
        Label(scrollable_frame, text="No tournaments found.", font=("Arial", 12), bg="#FFFFFF", fg="red").pack(pady=10)
    else:
        for tournament in result:
            # Frame for each tournament
            tournament_frame = Frame(scrollable_frame, bg="#F5F5F5", relief="solid", borderwidth=1, padx=10, pady=10)
            tournament_frame.pack(fill="x", pady=5)

            # Display tournament details
            tournament_info = (
                f"ID: {tournament['tournament_id']} | Name: {tournament['tournament_name']} "
                f"| Location: {tournament['location']} | Sport: {tournament['sport_type']} "
                f"| Start Date: {tournament['start_date']} | End Date: {tournament['end_date']}"
            )
            Label(tournament_frame, text=tournament_info, font=("Arial", 12), bg="#F5F5F5", anchor="w").pack(side="left", fill="x", expand=True)

            # Join button
            join_button = Button(
                tournament_frame, text="JOIN", font=("Arial", 10, "bold"), bg="#64B5F6", fg="white",
                command=lambda tid=tournament['tournament_id']: join_tournament(user_id, tid)
            )
            join_button.pack(side="right", padx=10)

    # Update scroll region
    scrollable_frame.update_idletasks()
    canvas.config(scrollregion=canvas.bbox("all"))

    # Footer with Close Button
    footer_frame = Frame(result_window, bg="#E3F2FD")
    footer_frame.pack(fill="x")
    Button(footer_frame, text="Close", font=("Arial", 12, "bold"), bg="red", fg="white", command=result_window.destroy).pack(pady=10)


def search_based_filter(location, sport,user_id ):
    # Placeholder: In a real application, this would query the database.
    messagebox.showinfo("Search Results", f"Searching for grounds...Location: {location}...Sport: {sport}")
    result = get_grounds_by_location_and_sport(location,sport)
    # Open a new window with the results (placeholder for actual result window)
    show_search_results(result , user_id)


def search_based_name(ground_name , user_id):
    # Placeholder: In a real application, this would query the database.
    messagebox.showinfo("Search Results", f"Searching for grounds :{ground_name}")
    result = get_grounds_by_name(ground_name)

    # Open a new window with the results (placeholder for actual result window)
    show_search_results(result , user_id)


def show_search_results(result, user_id):
    """
    Displays the search results in a new window with a View button for each ground.
    """
    # Create a new window to display search results
    result_window = tk.Toplevel()  # This creates a new top-level window (popup)
    result_window.title("Search Results")
    result_window.configure(bg="#E3F2FD")  # Set background color
    # Make the window fullscreen
    result_window.geometry(f"{result_window.winfo_screenwidth()}x{result_window.winfo_screenheight()}+0+0")

    # Header
    header_frame = Frame(result_window, bg="#64B5F6", height=50)
    header_frame.pack(fill="x")
    Label(header_frame, text="Search Results", font=("Arial", 16, "bold"), bg="#64B5F6", fg="white").pack(pady=10)

    # Main Frame for Results
    main_frame = Frame(result_window, bg="#E3F2FD", padx=15, pady=15)
    main_frame.pack(fill="both", expand=True)

    # Create a canvas and scrollbar for scrolling
    canvas = tk.Canvas(main_frame, bg="#E3F2FD", highlightthickness=0)
    scrollbar = tk.Scrollbar(main_frame, orient="vertical", command=canvas.yview)
    scrollable_frame = Frame(canvas, bg="#FFFFFF", padx=15, pady=15)

    # Configure canvas and scrollbar
    canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
    canvas.configure(yscrollcommand=scrollbar.set)
    canvas.pack(side="left", fill="both", expand=True)
    scrollbar.pack(side="right", fill="y")

    # Populate results
    if not result:
        Label(scrollable_frame, text="No grounds found based on your search criteria.", font=("Arial", 12), bg="#FFFFFF", fg="red").pack(pady=10)
    else:
        for ground in result:
            # Frame for each result
            ground_frame = Frame(scrollable_frame, bg="#F5F5F5", relief="solid", borderwidth=1, padx=10, pady=10)
            ground_frame.pack(fill="x", pady=5)

            # Display ground details
            ground_info = f"ID: {ground['ground_id']} | Name: {ground['ground_name']} | Location: {ground['location']} | Sport: {ground['sport_type']}"
            Label(ground_frame, text=ground_info, font=("Arial", 12), bg="#F5F5F5", anchor="w").pack(side="left", fill="x", expand=True)

            # View button
            view_button = Button(ground_frame, text="View", font=("Arial", 10, "bold"), bg="#64B5F6", fg="white",
                                 command=lambda g=ground: show_ground_details(g, user_id))
            view_button.pack(side="right", padx=10)

    # Update scroll region
    scrollable_frame.update_idletasks()
    canvas.config(scrollregion=canvas.bbox("all"))

    # Footer
    footer_frame = Frame(result_window, bg="#E3F2FD")
    footer_frame.pack(fill="x")
    Button(footer_frame, text="Close", font=("Arial", 12, "bold"), bg="red", fg="white", command=result_window.destroy).pack(pady=10)




def show_ground_details(ground, user_id):
    """
    Displays the details of a selected ground in a new window.
    """
    # Create a new top-level window
    detail_window = tk.Toplevel()
    detail_window.title(f"Details of {ground['ground_name']}")
    detail_window.configure(bg="#E3F2FD")  # Set background color
    # Make the window fullscreen
    detail_window.geometry(f"{detail_window.winfo_screenwidth()}x{detail_window.winfo_screenheight()}+0+0")

    # Header
    header_frame = tk.Frame(detail_window, bg="#64B5F6", height=50)
    header_frame.pack(fill="x")
    tk.Label(header_frame, text=f"Details of {ground['ground_name']}", font=("Arial", 16, "bold"), bg="#64B5F6", fg="white").pack(pady=10)

    # Main Frame for Details
    main_frame = tk.Frame(detail_window, bg="#FFFFFF", padx=20, pady=20)
    main_frame.pack(fill="both", expand=True)

    # Display the ground details
    ground_info = f"ID: {ground['ground_id']}\nName: {ground['ground_name']}\nLocation: {ground['location']}\nSport: {ground['sport_type']}"
    tk.Label(main_frame, text=ground_info, font=("Arial", 12), bg="#FFFFFF", anchor="w", justify="left").pack(pady=10, anchor="w")

    # Add a calendar for date selection
    calendar_label = tk.Label(main_frame, text="Select Date:", font=("Arial", 12, "bold"), bg="#FFFFFF")
    calendar_label.pack(pady=5, anchor="w")
    calendar = Calendar(main_frame, selectmode='day', date_pattern='yyyy-mm-dd')
    calendar.pack(pady=10)


    # Add a time slot selection combobox
    time_slot_label = tk.Label(main_frame, text="Select Time Slot:", font=("Arial", 12, "bold"), bg="#FFFFFF")
    time_slot_label.pack(pady=5, anchor="w")
    time_slots = ["Early Morning", "Morning", "Noon", "Afternoon", "Evening", "Night", "Midnight"]
    time_var = tk.StringVar(root)
    time_var.set("Morning")
    time_menu = tk.OptionMenu(main_frame, time_var, *time_slots)
    time_menu.pack(pady=10)
    # Add a Book button
    book_button = tk.Button(main_frame, text="Book", font=("Arial", 12, "bold"), bg="#64B5F6", fg="white",
                            command=lambda: book_ground(user_id, ground['ground_id'],calendar.get_date(),time_var.get()))
    book_button.pack(pady=20)

    # Footer
    footer_frame = tk.Frame(detail_window, bg="#E3F2FD")
    footer_frame.pack(fill="x")
    tk.Button(footer_frame, text="Close", font=("Arial", 12, "bold"), bg="red", fg="white", command=detail_window.destroy).pack(pady=10)


# Import the message handler functions
def book_ground(user_id, ground_id, selected_date, selected_time):
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
            SELECT * 
            FROM check_and_book(
                p_user_id := %s, 
                p_ground_id := %s, 
                p_booking_date := %s, 
                p_time_slot := %s
            );
        """, (user_id, ground_id, selected_date, selected_time))
        conn.commit()
        # Fetch the result (booking_id, message)
        result = cursor.fetchone()
        booking_id, message = result  # Unpack the result

    except Exception as e:
        # Handle any exception that occurs during the process
        raise Exception(f"Error occurred: {str(e)}")
    finally:
        # Close the cursor and the connection
        cursor.close()
        conn.close()
    
    if booking_id:
        # If booking is successful, display the success message
        messagebox.showinfo("Booking Confirmation", f"Booking ID: {booking_id}\n{message}")
        view_receipt(booking_id,user_id,ground_id)
        
    else:
        # If booking fails, display the error message
        messagebox.showerror("Booking Error", message)

def view_receipt(booking_id, user_id, ground_id):
    # Call get_receipts to fetch the receipt details
    results = get_receipts(booking_id, user_id, ground_id)
    
    if results:
        # If results are found, create a Toplevel window to show the receipt details
        receipt_window = tk.Toplevel()  # Create a new Toplevel window
        receipt_window.title("Receipt Details")  # Set window title
        receipt_window.geometry("300x300")  # Set the window size (optional)
        
        # Create and display the receipt details in the Toplevel window
        receipt_details = (
            f"Receipt ID: {results['receipt_id']}\n"
            f"Booking ID: {results['booking_id']}\n"
            f"User ID: {results['user_id']}\n"
            f"Ground ID: {results['ground_id']}\n"
            f"Total Amount: {results['total_amount']}\n"
            f"Issued At: {results['issued_at']}"
        )
        
        # Label to display the receipt details
        receipt_label = tk.Label(receipt_window, text=receipt_details, font=("Arial", 10), anchor="w", justify="left")
        receipt_label.pack(padx=10, pady=10)
        close_button = tk.Button(receipt_window, text="Close", command=receipt_window.destroy)
        close_button.pack(pady=10)
        
    else:
        # If no receipt is found, display an error message
        messagebox.showerror("Error","Receipt not found for the provided details.")







def handle_login():
    """
    Handles the login process and redirects the user based on their type.
    """
    email = email_entry.get()
    password = password_entry.get()
    user_type = user_type_var.get()

    # Ensure all fields are filled
    if not email or not password or user_type == "Select User Type":
        messagebox.showerror("Error", "All fields are required.")
        return

    try:
        # Call the validate_user function to check credentials
        user_id = validate_user(email, password, user_type)

        if user_id:
            # Success: Display success message and proceed
            messagebox.showinfo("Success", f"Login successful! Welcome, User ID: {user_id}.")
            root.destroy()  # Close the login window
            show_home_page(user_type, user_id)  # Redirect to the appropriate home page
        else:
            # Failure: Invalid credentials
            messagebox.showerror("Login Failed", "Invalid email, password, or user type. Please try again.")

    except Exception as e:
        # Handle unexpected errors
        messagebox.showerror("Unexpected Error", f"An unexpected error occurred: {e}")
        print(f"Unexpected Error: {e}")  # Debugging output

def open_fullscreen_home_page(user_type, user_id):
    """
    Open the home page for the user in full-screen mode.
    """
    # Create a new Tkinter window
    home_window = Tk()
    home_window.title(f"{user_type.capitalize()} Home Page")
    
    # Enable full-screen mode
    home_window.attributes("-fullscreen", True)

    # Add a button to exit full-screen mode
    def exit_fullscreen(event=None):
        home_window.attributes("-fullscreen", False)

    home_window.bind("<Escape>", exit_fullscreen)

    # Add a sample label and logout button for the home page
    Label(home_window, text=f"Welcome, {user_type.capitalize()} id: {user_id}!", font=("Arial", 16)).pack(pady=20)
    Button(home_window, text="Logout", command=home_window.destroy, bg="red", fg="white").pack(pady=20)

    # Run the home window
    home_window.mainloop()


# Enhanced Login Page Code
root = Tk()
root.title("Login Page")

# Enable Full-Screen Mode
root.attributes("-fullscreen", True)

# Allow exiting full-screen mode with Escape key
root.bind("<Escape>", lambda event: root.attributes("-fullscreen", False))

# Add a soft pastel blue background
root.configure(bg="#E3F2FD")  # Soft pastel blue

# Header
header_frame = Frame(root, bg="#64B5F6", height=60)  # Complementary blue for the header
header_frame.pack(fill="x")
Label(header_frame, text="Welcome to the Login Page", font=("Arial", 16, "bold"), bg="#64B5F6", fg="white").pack(pady=10)

# Main Frame
main_frame = Frame(root, bg="#E3F2FD", padx=20, pady=20)
main_frame.pack(expand=True)

# Email
Label(main_frame, text="Email:", font=("Arial", 12), bg="#E3F2FD").grid(row=0, column=0, sticky="w", pady=10)
email_entry = Entry(main_frame, font=("Arial", 12), width=30)
email_entry.grid(row=0, column=1, pady=10)

# Password
Label(main_frame, text="Password:", font=("Arial", 12), bg="#E3F2FD").grid(row=1, column=0, sticky="w", pady=10)
password_entry = Entry(main_frame, font=("Arial", 12), show="*", width=30)
password_entry.grid(row=1, column=1, pady=10)

# User Type
Label(main_frame, text="User Type:", font=("Arial", 12), bg="#E3F2FD").grid(row=2, column=0, sticky="w", pady=10)
user_type_var = StringVar()
user_type_var.set("Select User Type")
user_type_menu = OptionMenu(main_frame, user_type_var, "booking_user", "ground_owner", "superadmin")
user_type_menu.config(font=("Arial", 12), width=18)
user_type_menu.grid(row=2, column=1, pady=10)

# Login Button
login_button = Button(main_frame, text="Login", font=("Arial", 12, "bold"), bg="#64B5F6", fg="white", width=15,
                      command=lambda: handle_login())
login_button.grid(row=3, column=1, pady=20)

# Footer
footer_frame = Frame(root, bg="#E3F2FD")
footer_frame.pack(fill="x")
Label(footer_frame, text="© 2024 playo Clone. All Rights Reserved.", font=("Arial", 10), bg="#E3F2FD", fg="gray").pack(pady=10)

root.mainloop()

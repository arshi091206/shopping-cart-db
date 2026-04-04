from flask import Flask, request, jsonify
from flask_cors import CORS
import psycopg2
import psycopg2.extras
from datetime import datetime

app = Flask(__name__)
CORS(app)

DB_CONFIG = {
    'host':     'localhost',
    'dbname':   'shoppingcartdb',
    'user':     'postgres',
    'password': 'postgres',
    'port':     5432
}

def get_db():
    return psycopg2.connect(**DB_CONFIG)

def query(sql, params=(), fetchone=False):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute(sql, params)
    result = cur.fetchone() if fetchone else cur.fetchall()
    cur.close(); conn.close()
    return [dict(r) for r in result] if not fetchone else (dict(result) if result else None)

def execute(sql, params=()):
    conn = get_db()
    cur = conn.cursor()
    cur.execute(sql, params)
    last_id = cur.fetchone()[0]
    conn.commit(); cur.close(); conn.close()
    return last_id

@app.route('/')
def index():
    return jsonify({'status': 'ok'})

@app.route('/customers')
def get_customers():
    return jsonify(query("SELECT customer_id, name, email, phone, address FROM Customer"))

@app.route('/customers', methods=['POST'])
def create_customer():
    d = request.json
    cid = execute(
        "INSERT INTO Customer (name, email, phone, address) VALUES (%s,%s,%s,%s) RETURNING customer_id",
        (d['name'], d.get('email'), d.get('phone'), d.get('address'))
    )
    return jsonify({'customer_id': cid}), 201

@app.route('/items')
def get_items():
    return jsonify(query("SELECT item_id, item_name, description, price, stock_level, category FROM Item ORDER BY category, item_name"))

@app.route('/checkout', methods=['POST'])
def checkout():
    data = request.json
    customer_id = data.get('customer_id')
    cart_items  = data.get('items', [])
    if not customer_id or not cart_items:
        return jsonify({'error': 'customer_id and items required'}), 400

    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    try:
        # Check stock for every item
        for entry in cart_items:
            cur.execute("SELECT item_name, price, stock_level FROM Item WHERE item_id = %s FOR UPDATE", (entry['item_id'],))
            item = cur.fetchone()
            if not item:
                raise ValueError(f"Item ID {entry['item_id']} not found")
            if item['stock_level'] < entry['quantity']:
                raise ValueError(f"Insufficient stock for '{item['item_name']}'. Available: {item['stock_level']}")

        # Create cart
        cur.execute("INSERT INTO ShoppingCart (customer_id) VALUES (%s) RETURNING cart_id", (customer_id,))
        cart_id = cur.fetchone()['cart_id']

        # Add items and calculate total
        total = 0.0
        for entry in cart_items:
            cur.execute("SELECT price FROM Item WHERE item_id = %s", (entry['item_id'],))
            price = float(cur.fetchone()['price'])
            total += price * entry['quantity']
            cur.execute("INSERT INTO CartItem (cart_id, item_id, quantity) VALUES (%s,%s,%s)", (cart_id, entry['item_id'], entry['quantity']))

        total_with_tax = round(total * 1.18, 2)

        # Create order
        cur.execute(
            """INSERT INTO "Order" (customer_id, cart_id, purchase_date, total_amount, order_status)
               VALUES (%s,%s,%s,%s,'placed') RETURNING order_id""",
            (customer_id, cart_id, datetime.now(), total_with_tax)
        )
        order_id = cur.fetchone()['order_id']

        # Order items + deduct stock
        for entry in cart_items:
            cur.execute("SELECT price FROM Item WHERE item_id = %s", (entry['item_id'],))
            price = float(cur.fetchone()['price'])
            cur.execute("INSERT INTO OrderItem (order_id, item_id, quantity, price_at_purchase) VALUES (%s,%s,%s,%s)",
                        (order_id, entry['item_id'], entry['quantity'], price))
            cur.execute("UPDATE Item SET stock_level = stock_level - %s WHERE item_id = %s", (entry['quantity'], entry['item_id']))

        conn.commit()
        return jsonify({'order_id': order_id, 'total_amount': total_with_tax, 'message': f'Order #{order_id} placed!'}), 201

    except ValueError as ve:
        conn.rollback()
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        cur.close(); conn.close()

@app.route('/orders/<int:customer_id>')
def get_orders(customer_id):
    orders = query("""SELECT order_id, customer_id, purchase_date, total_amount, order_status
                      FROM "Order" WHERE customer_id = %s ORDER BY purchase_date DESC""", (customer_id,))
    for o in orders:
        o['purchase_date'] = o['purchase_date'].isoformat() if o['purchase_date'] else None
        o['total_amount']  = float(o['total_amount'])
        items = query("""SELECT oi.item_id, i.item_name, oi.quantity, oi.price_at_purchase
                         FROM OrderItem oi JOIN Item i ON oi.item_id = i.item_id
                         WHERE oi.order_id = %s""", (o['order_id'],))
        for item in items:
            item['price_at_purchase'] = float(item['price_at_purchase'])
        o['items'] = items
    return jsonify(orders)

if __name__ == '__main__':
    print("\n  ShoppingCart API (PostgreSQL)")
    print("  Running at: http://localhost:5000\n")
    app.run(debug=True, port=5000)
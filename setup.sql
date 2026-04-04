-- ============================================================
--  Shopping Cart System — Complete SQL Setup
--  CSS_2212 Database Systems Lab
--  Run this file first before starting the backend
-- ============================================================

-- 1. Create and select the database
DROP DATABASE IF EXISTS ShoppingCartDB;
CREATE DATABASE ShoppingCartDB;
USE ShoppingCartDB;

-- ============================================================
--  TABLES
-- ============================================================

CREATE TABLE Customer (
    customer_id INT PRIMARY KEY AUTO_INCREMENT,
    name        VARCHAR(100) NOT NULL,
    email       VARCHAR(100) UNIQUE,
    phone       VARCHAR(15),
    address     TEXT
);

CREATE TABLE Item (
    item_id     INT PRIMARY KEY AUTO_INCREMENT,
    item_name   VARCHAR(100) NOT NULL,
    description TEXT,
    price       DECIMAL(10,2) NOT NULL CHECK (price > 0),
    stock_level INT NOT NULL DEFAULT 0 CHECK (stock_level >= 0),
    category    VARCHAR(50)
);

CREATE TABLE ShoppingCart (
    cart_id     INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES Customer(customer_id)
);

CREATE TABLE CartItem (
    cart_id     INT,
    item_id     INT,
    quantity    INT NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (cart_id, item_id),
    FOREIGN KEY (cart_id) REFERENCES ShoppingCart(cart_id),
    FOREIGN KEY (item_id) REFERENCES Item(item_id)
);

CREATE TABLE `Order` (
    order_id      INT PRIMARY KEY AUTO_INCREMENT,
    customer_id   INT NOT NULL,
    cart_id       INT NOT NULL,
    purchase_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    total_amount  DECIMAL(10,2) NOT NULL,
    order_status  ENUM('placed','pending','cancelled') DEFAULT 'pending',
    FOREIGN KEY (customer_id) REFERENCES Customer(customer_id),
    FOREIGN KEY (cart_id)     REFERENCES ShoppingCart(cart_id)
);

CREATE TABLE OrderItem (
    order_id          INT,
    item_id           INT,
    quantity          INT NOT NULL,
    price_at_purchase DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (order_id, item_id),
    FOREIGN KEY (order_id) REFERENCES `Order`(order_id),
    FOREIGN KEY (item_id)  REFERENCES Item(item_id)
);

-- ============================================================
--  TRIGGER: prevent stock from going below zero
-- ============================================================
DELIMITER $$
CREATE TRIGGER prevent_negative_stock
BEFORE UPDATE ON Item
FOR EACH ROW
BEGIN
    IF NEW.stock_level < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Stock level cannot go below zero';
    END IF;
END$$
DELIMITER ;

-- ============================================================
--  STORED PROCEDURE: CheckoutCart (for direct SQL demo)
-- ============================================================
DELIMITER $$
CREATE PROCEDURE CheckoutCart(IN p_cart_id INT, IN p_customer_id INT)
BEGIN
    DECLARE done      INT DEFAULT 0;
    DECLARE v_item_id INT;
    DECLARE v_qty     INT;
    DECLARE v_stock   INT;
    DECLARE v_price   DECIMAL(10,2);
    DECLARE v_total   DECIMAL(10,2) DEFAULT 0;
    DECLARE v_order   INT;
    DECLARE bad_stock BOOLEAN DEFAULT FALSE;

    DECLARE cart_cur CURSOR FOR
        SELECT ci.item_id, ci.quantity, i.stock_level, i.price
        FROM CartItem ci JOIN Item i ON ci.item_id = i.item_id
        WHERE ci.cart_id = p_cart_id;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    START TRANSACTION;

    OPEN cart_cur;
    chk: LOOP
        FETCH cart_cur INTO v_item_id, v_qty, v_stock, v_price;
        IF done THEN LEAVE chk; END IF;
        IF v_qty > v_stock THEN
            SET bad_stock = TRUE;
            LEAVE chk;
        END IF;
        SET v_total = v_total + (v_qty * v_price);
    END LOOP;
    CLOSE cart_cur;

    IF bad_stock THEN
        ROLLBACK;
        SELECT 'CHECKOUT FAILED: Insufficient stock for one or more items.' AS message;
    ELSE
        INSERT INTO `Order`(customer_id, cart_id, total_amount, order_status)
        VALUES (p_customer_id, p_cart_id, v_total * 1.18, 'placed');

        SET v_order = LAST_INSERT_ID();

        INSERT INTO OrderItem(order_id, item_id, quantity, price_at_purchase)
        SELECT v_order, ci.item_id, ci.quantity, i.price
        FROM CartItem ci JOIN Item i ON ci.item_id = i.item_id
        WHERE ci.cart_id = p_cart_id;

        UPDATE Item i JOIN CartItem ci ON i.item_id = ci.item_id
        SET i.stock_level = i.stock_level - ci.quantity
        WHERE ci.cart_id = p_cart_id;

        COMMIT;
        SELECT CONCAT('Order #', v_order, ' placed! Total: Rs.', ROUND(v_total * 1.18, 2)) AS message;
    END IF;
END$$
DELIMITER ;

-- ============================================================
--  SAMPLE DATA
-- ============================================================

INSERT INTO Customer (name, email, phone, address) VALUES
('Arshi Garg',          'arshi@email.com',     '9876543210', 'Koramangala, Bangalore'),
('Nithyashree Hebbar',  'nithya@email.com',    '9123456789', 'Mangalore, Karnataka'),
('Shreya Jain',         'shreya@email.com',    '9988776655', 'Andheri, Mumbai'),
('Taneesha Rajiv',      'taneesha@email.com',  '9871234560', 'Connaught Place, Delhi');

INSERT INTO Item (item_name, description, price, stock_level, category) VALUES
('Wireless Mouse',    'Ergonomic Bluetooth mouse, 3-year battery',   799.00,  50, 'Electronics'),
('Mechanical Keyboard','RGB backlit, TKL layout, Cherry MX switches',3499.00, 20, 'Electronics'),
('USB-C Hub',         '7-in-1 multiport hub with 4K HDMI',          1499.00, 30, 'Electronics'),
('Laptop Stand',      'Adjustable aluminium stand, foldable',        1299.00, 15, 'Electronics'),
('Notebook A5',       'Hardcover ruled notebook, 200 pages',          149.00, 200, 'Stationery'),
('Pen Set',           'Pack of 10 gel pens, assorted colours',         99.00,   0, 'Stationery'),
('Sticky Notes',      '3x3 inches, 5 colours, 100 sheets each',       199.00,  80, 'Stationery'),
('Desk Lamp',         'LED, adjustable arm, 3 colour temps',          999.00,  25, 'Furniture'),
('Monitor Riser',     'Bamboo monitor stand with drawer',             649.00,  12, 'Furniture'),
('Cable Organiser',   'Under-desk cable management tray',             349.00,   5, 'Furniture');

-- ============================================================
--  VERIFY SETUP
-- ============================================================
SELECT 'Setup complete!' AS status;
SELECT COUNT(*) AS total_customers FROM Customer;
SELECT COUNT(*) AS total_items FROM Item;
SELECT item_name, price, stock_level FROM Item ORDER BY category;

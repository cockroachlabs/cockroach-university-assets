
#!/bin/bash
set -euxo pipefail
## ADDING MYSQL CONFIGURATION
echo "[INFO] Adding MySQL configuration..."
cat > /etc/mysql/conf.d/my.cnf <<EOF
[mysqld]
gtid_mode = ON
enforce_gtid_consistency = ON
log_slave_updates = ON
server_id = 101
log_bin = mysql-bin
binlog_format = ROW
binlog_row_metadata = FULL
binlog_row_image = FULL
EOF

## RESTARTING MYSQL
echo "[INFO] Restarting MySQL..."
sudo systemctl restart mysql

## ADDING USERS MYSQL
echo "[INFO] Adding MySQL users..."
mysql -e "create user 'crmuser'@'localhost' identified by 'crmpwd';"
mysql -e "grant all privileges on crm.* to 'crmuser'@'localhost';"
mysql -e "grant select, reload, replication slave, replication client ON *.* TO 'crmuser'@'localhost';"
mysql -e "grant select on mysql.gtid_executed to 'crmuser'@'localhost';"
mysql -e "flush privileges;"

## CREATE SCHEMAS DIRECTORY
echo "[INFO] Creating schemas directory..."
SCHEMAS=/root/cockroachdb/schemas
mkdir -p $SCHEMAS

##
# MySQL
##
echo "[INFO] Creating MySQL schema..."
cat > $SCHEMAS/schema_mysql.sql <<EOF

CREATE DATABASE IF NOT EXISTS crm;
USE crm;

DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id INT PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(20),
    address VARCHAR(255)
)
COLLATE='utf8_unicode_ci'
ENGINE=InnoDB;

DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    order_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT,
    order_date DATE,
    total_amount DECIMAL(10, 2),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
)
COLLATE='utf8_unicode_ci'
ENGINE=InnoDB;

LOCK TABLES customers WRITE;
INSERT INTO  customers VALUES
(1,'Marilie','Botsford','turner.ole@example.org','(725)458-4653x19898','44077 Fabian Isle\nJastbury, MD 53709-9034'),
(2,'Theo','Mayert','haylie04@example.com','047.511.3392','7246 Harley Mount\nAlvinamouth, MN 65625-2689'),
(3,'Golda','Koss','santiago94@example.org','+44(9)5616906934','11532 Strosin Junction Suite 799\nChristopherton, AL 62634-7760'),
(4,'Jovan','Terry','tod53@example.net','+42(5)0903990462','238 Upton Meadows Suite 851\nEast Nashton, OK 99605-1885'),
(5,'Nikki','Greenholt','zachary47@example.com','178-395-8648','0951 Abe Crossing Suite 480\nCorkerytown, AZ 31155-9883'),
(6,'Rosemarie','Runolfsson','tiffany28@example.org','(565)698-1756','14997 Runolfsson Square\nZenaberg, FL 69918-6304'),
(7,'Charlene','Kassulke','vshanahan@example.org','(452)907-4632','80742 Elvera Fields Apt. 045\nSouth Nicolettetown, DC 60166'),
(8,'Ethelyn','Wilkinson','boyer.jovan@example.org','079-819-7527x209','60140 Legros Isle\nSouth Glennieborough, FL 13245'),
(9,'Durward','Swaniawski','kamren30@example.org','(070)568-5570','659 Imelda Ranch Apt. 418\nJasonland, AL 64401'),
(10,'Richmond','Watsica','stiedemann.thomas@example.org','+68(2)5943982916','31611 Benedict Track Apt. 758\nPort Jany, DE 82281');
UNLOCK TABLES;

LOCK TABLES orders WRITE;
INSERT INTO orders VALUES
(1,1,'1998-10-21',2706.92),
(2,2,'2017-11-21',62.69),
(3,3,'1996-09-21',2.00),
(4,4,'1976-09-07',2756867.90),
(5,5,'1995-05-21',168615.37),
(6,6,'2020-04-06',1.70),
(7,7,'1984-11-03',808499.10),
(8,8,'1972-09-26',73155918.00),
(9,9,'2010-08-07',99999999.99),
(10,10,'1985-09-07',1785454.07),
(11,1,'1995-10-19',3.47),
(12,2,'2011-01-12',918.82),
(13,3,'1974-03-01',1.16),
(14,4,'1991-02-01',421.40),
(15,5,'1981-07-17',453.15),
(16,6,'2005-03-21',7746272.26),
(17,7,'2016-04-12',99999999.99),
(18,8,'2016-01-13',2.68),
(19,9,'1987-08-16',0.84),
(20,10,'1983-12-13',11835145.00),
(21,1,'1980-04-26',4344397.94),
(22,2,'1994-02-16',4268.77),
(23,3,'2017-12-18',37006640.65),
(24,4,'1981-07-02',7867812.20),
(25,5,'1979-03-30',31101.48),
(26,6,'1986-01-26',1241.80),
(27,7,'1973-01-30',4017.80),
(28,8,'2003-01-07',0.44),
(29,9,'2002-01-05',44.32),
(30,10,'1990-11-07',0.00),
(31,1,'2017-10-01',5078.88),
(32,2,'2011-06-22',49480.07),
(33,3,'2006-05-17',0.00),
(34,4,'1988-01-11',0.00),
(35,5,'2019-04-10',297166.56),
(36,6,'1982-05-29',26425.00),
(37,7,'2008-11-17',99999999.99),
(38,8,'2008-08-15',0.00),
(39,9,'2013-04-28',1829.77),
(40,10,'2011-04-18',6089.80),
(41,1,'2024-11-26',99999999.99),
(42,2,'2020-05-07',1683718.35),
(43,3,'2017-03-17',2974.53),
(44,4,'1992-02-25',24.90),
(45,5,'1985-08-15',15657.49),
(46,6,'2000-03-24',159399.11),
(47,7,'1974-03-02',11.50),
(48,8,'2017-11-04',7.70),
(49,9,'1995-03-18',552.29),
(50,10,'1999-07-18',9032.61);
UNLOCK TABLES;

EOF

if [ -f $SCHEMAS/schema_mysql.sql ]; then
    echo "[INFO] Executing MySQL schema..."
    mysql < $SCHEMAS/schema_mysql.sql
fi
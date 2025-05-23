#!/bin/bash
set -euxo pipefail

##
# Postgres
##
# Create schemas directory
echo "[INFO] Installing PostgreSQL databases..."
SCHEMAS=/root/cockroachdb/schemas
mkdir -p $SCHEMAS

echo "[INFO] Creating PostgreSQL schema..."
cat > $SCHEMAS/schema_postgres.sql <<EOF

CREATE DATABASE logistics;

\c logistics


CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    product_name VARCHAR(255),
    description TEXT,
    price DECIMAL(10, 2)
);

CREATE TABLE inventory (
    inventory_id SERIAL PRIMARY KEY,
    product_id INT,
    quantity INT,
    location VARCHAR(255),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

CREATE TABLE shipments (
    shipment_id SERIAL PRIMARY KEY,
    order_id INT,
    product_id INT,
    quantity INT,
    shipment_date DATE,
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

INSERT INTO products VALUES
(1,'est','Ipsam quisquam quasi doloribus aut ex voluptatem tempora. Consectetur unde enim itaque qui sunt ea sit et. Neque aut sit aliquid voluptatibus molestiae reprehenderit ut quo. Aspernatur aut sequi nesciunt voluptates eius. Minima veniam non aut dolorem.',2000154.33),
(2,'velit','Quidem laborum vero et eos. Dolores iure autem nostrum vel sit voluptatem delectus qui. Eum est ad quis ducimus placeat repudiandae. Ut temporibus iste dicta animi laborum aut porro.',99999999.99),
(3,'necessitatibus','Veniam eos qui omnis nulla modi quas. In blanditiis at id molestiae ipsum officiis facere accusamus. Dolor sit et qui facere eveniet ratione.',646.89),
(4,'ea','Quos eveniet nemo dolores expedita ipsa alias debitis. Est voluptatem officiis qui omnis et quia. Voluptatem ea et sed quasi totam totam debitis cumque.',3534309.85),
(5,'corporis','Nulla odio commodi nostrum distinctio debitis qui. Et deserunt perspiciatis voluptatem nostrum unde. Ducimus eligendi omnis voluptatum ut. Qui blanditiis inventore cupiditate.',3326044.25),
(6,'asperiores','Vel dolores cum quia tempora. Velit pariatur sint veniam dolorum velit. Deserunt asperiores praesentium repellendus ea impedit.',2278104.00),
(7,'similique','Ut blanditiis qui cumque sequi ipsa voluptatem. A officia in in culpa consectetur qui ut. Quo quia tempora voluptatum aut nihil.',0.00),
(8,'harum','Hic tenetur laborum voluptatem laboriosam dolores repellendus illum voluptas. Autem non esse sint in eum. Omnis molestiae non dolorum. Ea non illum repellat eaque enim tempore ea eos.',5.00),
(9,'enim','Earum qui quia libero ipsam ut. Nobis tempora ea in sint id cumque. Consequatur non cupiditate non et sapiente omnis.',19327.20),
(10,'quidem','Ut inventore expedita ut corrupti. Harum explicabo unde ab. Magnam suscipit aut cupiditate rerum ducimus qui quia. Et dolorum quisquam asperiores quia.',99999999.99);


INSERT INTO inventory VALUES
(1,1,82490205,'9556 Halie Islands Suite 693\nCobyborough, MS 23510-1194'),
(2,2,92105,'459 Palma Corner Apt. 997\nPort Marilie, SD 51244-5037'),
(3,3,19,'01486 Brakus Stream\nSwaniawskihaven, VT 66158-4119'),
(4,4,27,'67821 Runolfsson Park\nTyrellmouth, WV 26896-3442'),
(5,5,28,'12806 Lowell Fields\nWizaside, TN 56618-0120'),
(6,6,1223,'844 Pat Coves\nKoelpinmouth, CA 28817-2171'),
(7,7,0,'46270 Taylor Station Suite 864\nSouth Einoton, AZ 83524-8712'),
(8,8,0,'34314 Padberg Unions Apt. 241\nKeeleyfort, NH 89935-8567'),
(9,9,55431,'8367 Andreane Groves Suite 671\nNew Reneefurt, HI 18280'),
(10,10,0,'918 Royce Summit Suite 609\nMurphyside, MN 20389-8419'),
(11,1,7,'43280 Altenwerth Expressway Suite 039\nEast Jacinthe, DC 64795-1032'),
(12,2,93137,'948 Wilhelm Ways Suite 008\nMrazland, WV 17022-9210'),
(13,3,10810006,'68194 Jaiden Fort Suite 597\nPourosbury, VA 76674'),
(14,4,33,'2009 Boyd Prairie Suite 041\nSouth Monserratton, OK 81783-4283'),
(15,5,12391,'27873 Hanna Light\nDominiqueshire, TN 02096-5023'),
(16,6,246157,'51624 Volkman Bypass\nWest Waltonmouth, KY 79452-5957'),
(17,7,662979902,'8683 Tiffany Oval Suite 858\nBrauliofort, AR 21052'),
(18,8,24015,'497 Ondricka Underpass\nFisherton, WI 70909'),
(19,9,0,'983 Bins Flats Apt. 531\nWest Tyshawnshire, TN 94262-1397'),
(20,10,205984880,'410 Korbin Vista Apt. 243\nConradborough, KY 14914-9369'),
(21,1,3,'85178 Orval Port\nBrockside, MS 67590-3504'),
(22,2,0,'849 Robb Garden Suite 225\nNew Khalidmouth, MN 66484'),
(23,3,15999456,'658 Simone Dale\nPort Jonville, RI 65957-2368'),
(24,4,581649,'789 Nitzsche Greens\nGaylordfurt, WI 46803'),
(25,5,548778,'662 O''Hara Extensions Suite 690\nNew Augustafort, OK 34321'),
(26,6,19,'40729 Florian Knolls Apt. 657\nPort Elroyport, VA 30440-8512'),
(27,7,23457162,'09312 Ignatius Groves\nNew Virgie, AR 22035-2809'),
(28,8,148070,'65030 Emmerich Island Suite 300\nNew Tamaraburgh, IN 97268-7200'),
(29,9,13,'19731 Kulas Glen\nNelsborough, CO 63848'),
(30,10,12330,'16197 Odessa Ferry\nNorth Catherine, MT 35128-5531'),
(31,1,5,'9647 Rath Via Apt. 774\nPort Rosalee, AZ 13665-9663'),
(32,2,6147,'88508 Conn Throughway\nSouth Vance, UT 19985-4971'),
(33,3,0,'00917 Gerhold Estates\nGabriellemouth, RI 56223'),
(34,4,1,'3845 Beverly Route\nPort Dangelomouth, PA 27300-8300'),
(35,5,896748,'1049 Weldon Spring Suite 877\nHeaneyside, WY 65791'),
(36,6,823679,'6480 Herzog Radial Apt. 110\nLake Juwanside, TN 80377'),
(37,7,226508,'961 Consuelo Rest Suite 767\nNorth Leannatown, OK 92085'),
(38,8,253936,'154 Cruickshank Curve\nHarveyton, RI 70207-1334'),
(39,9,34580,'87824 Stiedemann Lane Suite 174\nO''Reillyfurt, NE 70995-1431'),
(40,10,354149757,'81293 Hayley Ramp Apt. 690\nPort Caleb, DC 87119-5686'),
(41,1,17,'65204 Torp Pass\nD''Amoreview, MT 34538'),
(42,2,4117,'390 Farrell Inlet Apt. 932\nEast Jackeline, MA 65653-7444'),
(43,3,6640,'746 Rosenbaum Haven Suite 843\nLake Libbyview, DC 54243-9446'),
(44,4,0,'40687 Sallie Path\nJacobsonhaven, VA 70278'),
(45,5,0,'49921 Keebler Forks\nNew Bonnie, MA 42286-6049'),
(46,6,3,'97070 Sabrina Expressway Apt. 951\nBartellchester, NY 41649-3917'),
(47,7,55573804,'9720 Kozey Groves Suite 650\nNorth Wilfordhaven, TN 70896-5683'),
(48,8,7278520,'71781 Ziemann Heights\nTommiebury, NJ 90094-0201'),
(49,9,6116459,'2066 Mills Plaza\nNorth Alvis, MN 93118-2179'),
(50,10,76803,'973 Jonathon Green Apt. 088\nLafayettebury, VA 98669-5128'),
(51,1,0,'915 Hermiston Loop\nSouth Nettieborough, MS 88540'),
(52,2,395545,'65784 Koch Spurs\nPort Payton, SC 74434'),
(53,3,3920,'431 Kris Ferry\nEast Rodolfo, GA 37413'),
(54,4,0,'5245 Ernser Hill\nLoweshire, OR 98198-5251'),
(55,5,27788,'15792 Mae Mountains\nPort Ardenville, MS 99731'),
(56,6,9022280,'857 Runolfsson Mount Suite 383\nLake Tara, RI 39630'),
(57,7,349123,'13166 Altenwerth Summit\nBartonberg, HI 12143-4029'),
(58,8,30283,'619 Beatty Springs\nGinoview, OH 33561-9415'),
(59,9,0,'3268 Renner Land Apt. 510\nLamonthaven, WV 55796-3370'),
(60,10,1051248,'66532 Koch Inlet Suite 175\nBorisstad, UT 44611-4270'),
(61,1,162854,'587 Ariane Pike\nSouth Tommie, NJ 13868'),
(62,2,251880,'97119 Conroy Plaza\nWest Stanley, TX 74992-4079'),
(63,3,0,'592 Braun Forges Suite 479\nSchadenshire, VA 32665-1162'),
(64,4,6589814,'264 Powlowski Views\nBoganton, NH 86790-3623'),
(65,5,4,'4890 Lela Villages\nTorphymouth, SD 52124-6122'),
(66,6,28,'81386 Clementina Hollow\nNorth Zionton, SD 41926-3794'),
(67,7,0,'93727 Salma Walks\nWest Keyshawnhaven, IA 73578-4658'),
(68,8,4349033,'746 Murphy Parkway\nBatzfurt, VA 98839'),
(69,9,174,'02447 Janiya Plaza Apt. 018\nLake Erika, MI 83923-6086'),
(70,10,301,'0900 Andy Mall\nEast Rogersborough, TX 01755'),
(71,1,521,'634 Obie Harbor Apt. 123\nBlickfort, AK 75263-8346'),
(72,2,0,'58098 Alfred Roads\nLake Lucianoport, KY 58297'),
(73,3,471105090,'7361 Rocio Park Suite 909\nNorth Clarissastad, WI 04272-3583'),
(74,4,0,'68457 Harris Drive\nWest Bennychester, NV 19114'),
(75,5,297577241,'87335 Audreanne Parkways\nNorth Alvera, PA 35579-4948'),
(76,6,0,'6584 Jefferey Harbor Apt. 829\nMaurineport, RI 23111-6967'),
(77,7,10,'16095 Brianne Islands\nEast Bernitaborough, ME 71765-8986'),
(78,8,35,'45455 Damian Shores\nNorth Bernadinefurt, WY 17317'),
(79,9,8,'91633 Madisyn Fall Suite 664\nCaitlynport, DE 80988-4873'),
(80,10,18,'979 Connelly Valley Apt. 920\nPort Kenna, UT 11032-0676'),
(81,1,242141853,'8069 Gleason Ports\nEphraimland, OR 72344-9459'),
(82,2,996,'2393 Lourdes Canyon\nPort Dejahland, VA 45138-3483'),
(83,3,820050731,'580 Tanner Lodge\nLaurettaton, MD 51650'),
(84,4,72609,'0286 Mike Rest\nWest Luisaland, NV 11937-5701'),
(85,5,248622,'16867 Ariane Club Suite 964\nBetteberg, OR 94638'),
(86,6,59,'987 Jeanette Street Suite 179\nDaishaberg, AK 77663-2296'),
(87,7,22,'656 Kemmer Stravenue\nAliburgh, NH 87624-3426'),
(88,8,463904,'27122 Reuben Way Apt. 250\nJuliantown, MD 50295'),
(89,9,1830220,'925 Connelly Manors\nPort Phyllis, CT 58928'),
(90,10,12510876,'15093 Bergstrom Lock\nPort Houston, MO 43941-4264'),
(91,1,5,'6871 Aileen Burg Apt. 500\nAdrianatown, WY 66845-2202'),
(92,2,98321481,'51053 Eldora Trafficway\nSouth Magnolia, DC 71908'),
(93,3,376,'88737 Schroeder Pike\nBarrowsland, SC 16903-9006'),
(94,4,142289957,'17446 Funk Fork\nNorth Deeburgh, ME 58164'),
(95,5,41904,'65457 Violet Locks\nNew Henriberg, GA 03300-9947'),
(96,6,511274717,'01140 Flatley Plaza\nMonafort, NM 31144'),
(97,7,0,'6496 Hilll Knolls\nDonnellyland, GA 98369-3153'),
(98,8,293020,'44435 Trantow Well\nFredrickfort, DE 88676'),
(99,9,1641,'3874 Nedra Valleys Apt. 462\nLubowitzburgh, NJ 61461'),
(100,10,53108,'065 Koelpin Springs Suite 104\nEzequielmouth, NY 45616');

INSERT INTO shipments VALUES
(1,29,1,2599,'1998-10-11'),
(2,42,2,8359,'1970-06-20'),
(3,29,3,1,'2012-12-28'),
(4,10,4,727,'2010-08-13'),
(5,15,5,41205435,'1973-06-28'),
(6,41,6,0,'1995-08-24'),
(7,3,7,0,'1998-03-30'),
(8,39,8,8411976,'1997-02-12'),
(9,19,9,449760078,'2002-07-07'),
(10,16,10,1663,'1994-10-14'),
(11,1,1,3047879,'2017-03-16'),
(12,30,2,580,'1973-09-23'),
(13,9,3,156390371,'1998-07-17'),
(14,37,4,8996999,'2013-07-24'),
(15,43,5,123306,'2004-08-14'),
(16,13,6,8,'1993-02-07'),
(17,14,7,7512979,'1992-11-07'),
(18,50,8,36209007,'1998-02-20'),
(19,36,9,4924972,'1995-10-20'),
(20,31,10,6233160,'2017-05-23'),
(21,9,1,2101601,'1979-12-24'),
(22,44,2,2819,'1995-09-11'),
(23,1,3,47210,'1992-07-14'),
(24,44,4,0,'2008-09-14'),
(25,36,5,1,'2023-07-22'),
(26,7,6,7967915,'1981-08-27'),
(27,6,7,55,'1977-04-29'),
(28,49,8,230149,'2004-02-10'),
(29,27,9,1,'1995-07-01'),
(30,42,10,101,'2009-05-20'),
(31,17,1,3,'1991-05-10'),
(32,4,2,25170560,'1985-09-07'),
(33,27,3,77598,'1990-01-19'),
(34,38,4,3285747,'1994-08-10'),
(35,9,5,7070,'2009-09-24'),
(36,30,6,598,'1987-01-21'),
(37,16,7,808709,'2012-12-22'),
(38,47,8,1194453,'2017-05-14'),
(39,30,9,26047,'1984-02-21'),
(40,38,10,40559,'2019-08-20'),
(41,16,1,0,'2008-09-05'),
(42,2,2,174,'1975-08-20'),
(43,16,3,9504600,'2012-07-06'),
(44,13,4,22815114,'1970-07-23'),
(45,7,5,0,'1983-05-16'),
(46,34,6,2,'2004-03-24'),
(47,45,7,12542,'1998-07-09'),
(48,47,8,69,'1996-11-27'),
(49,34,9,0,'1982-02-23'),
(50,48,10,1077,'1997-03-19'),
(51,43,1,206120,'1970-11-24'),
(52,5,2,216,'1975-05-11'),
(53,41,3,1021,'2011-09-15'),
(54,43,4,0,'2018-08-04'),
(55,34,5,0,'2013-03-26'),
(56,28,6,2483,'2020-04-26'),
(57,3,7,221191490,'1991-05-13'),
(58,19,8,8959418,'1970-08-16'),
(59,43,9,80462308,'1971-03-16'),
(60,15,10,33608369,'1993-07-24'),
(61,25,1,3383,'1991-03-12'),
(62,30,2,67,'2001-04-26'),
(63,20,3,273293,'2002-09-22'),
(64,6,4,4227561,'2017-05-26'),
(65,50,5,0,'2006-01-13'),
(66,27,6,65,'1972-04-29'),
(67,50,7,229210450,'2009-06-05'),
(68,45,8,2,'2004-12-03'),
(69,33,9,0,'2024-03-16'),
(70,10,10,6592,'1982-04-18'),
(71,20,1,0,'2020-08-01'),
(72,28,2,5844,'2021-09-09'),
(73,32,3,4,'1995-05-06'),
(74,37,4,4,'1994-03-04'),
(75,3,5,0,'1998-11-01'),
(76,25,6,569031835,'2015-12-12'),
(77,42,7,19895,'1987-07-18'),
(78,10,8,219123,'1982-11-18'),
(79,4,9,0,'1984-10-12'),
(80,33,10,6907,'2009-09-15'),
(81,48,1,2490008,'2014-05-24'),
(82,22,2,1236615,'1995-02-10'),
(83,49,3,11885390,'2002-06-06'),
(84,27,4,42,'1978-11-19'),
(85,15,5,0,'2015-07-23'),
(86,30,6,0,'2018-11-14'),
(87,15,7,61,'1975-10-21'),
(88,38,8,2336,'2025-03-24'),
(89,18,9,11293,'1983-08-29'),
(90,27,10,48482,'2020-01-20'),
(91,12,1,4553,'2009-12-05'),
(92,43,2,9310,'1986-06-16'),
(93,50,3,308,'1977-04-10'),
(94,49,4,643423185,'1993-08-31'),
(95,46,5,2259347,'1993-11-09'),
(96,26,6,2601432,'1990-06-15'),
(97,41,7,46,'2009-07-10'),
(98,39,8,1080053,'1992-05-10'),
(99,20,9,3550873,'2017-03-24'),
(100,41,10,2185,'1984-09-21'),
(101,2,1,44,'1971-07-21'),
(102,36,2,2492646,'2002-08-27'),
(103,10,3,436156,'1998-08-13'),
(104,35,4,1388,'1992-07-02'),
(105,6,5,744041,'2001-11-06'),
(106,37,6,248168,'1998-03-23'),
(107,17,7,0,'1980-01-06'),
(108,28,8,1683529,'1996-11-11'),
(109,19,9,5381,'2000-05-15'),
(110,10,10,5066,'2012-02-03'),
(111,47,1,5,'1997-05-12'),
(112,44,2,13935,'2023-09-23'),
(113,15,3,125,'1991-03-29'),
(114,45,4,109,'2008-01-26'),
(115,1,5,13348797,'1977-08-04'),
(116,35,6,351423,'1992-09-29'),
(117,3,7,754,'1994-06-21'),
(118,32,8,49819,'2024-04-15'),
(119,42,9,8587379,'1983-10-12'),
(120,13,10,7,'2004-02-13'),
(121,42,1,287418,'2016-07-16'),
(122,42,2,16158,'1995-05-12'),
(123,19,3,262949159,'2014-06-22'),
(124,15,4,8,'1985-11-29'),
(125,28,5,0,'1972-02-10'),
(126,26,6,6,'1989-05-10'),
(127,28,7,30,'2015-04-01'),
(128,11,8,97510508,'1979-06-19'),
(129,50,9,254820,'1986-10-01'),
(130,13,10,298,'2008-03-30'),
(131,22,1,788626,'2020-08-22'),
(132,5,2,519161662,'1996-08-14'),
(133,20,3,0,'1976-06-10'),
(134,12,4,11938,'1998-12-18'),
(135,14,5,172,'2018-03-07'),
(136,49,6,420,'1977-03-31'),
(137,50,7,12,'2014-12-14'),
(138,13,8,8,'1989-07-13'),
(139,37,9,16,'1993-02-09'),
(140,26,10,66046,'1978-04-27'),
(141,19,1,13,'2011-02-05'),
(142,19,2,492,'2000-12-09'),
(143,3,3,0,'2001-09-03'),
(144,15,4,0,'2018-03-17'),
(145,13,5,166635939,'1974-07-31'),
(146,37,6,5,'1974-07-23'),
(147,27,7,500,'1972-03-16'),
(148,16,8,816,'1975-08-12'),
(149,40,9,7546104,'1980-02-01'),
(150,33,10,518678176,'2025-01-04');

EOF


if [ -f $SCHEMAS/schema_postgres.sql ]; then
    echo "[INFO] Executing PostgreSQL schema..."
    sudo -u postgres psql -d postgres < $SCHEMAS/schema_postgres.sql
fi

## Adding the User
echo "[INFO] Creating PostgreSQL user..."
sudo -u postgres psql -c "create role logistics_user with superuser login password 'lpwd';"
sudo -u postgres psql -c "alter database logistics OWNER TO logistics_user;"
PG_CONFIG=/etc/postgresql/16/main/pg_hba.conf
NEW_AUTH_METHOD="scram-sha-256"
sed -i.bak '/^local\s\+all\s\+all\s\+/ s/peer$/'"$NEW_AUTH_METHOD"'/' "$PG_CONFIG"

echo "[INFO] Restarting PostgreSQL service..."
sudo systemctl restart postgresql

echo "[INFO] Setting sequence values..."
cat > /usr/local/bin/fix-postgres.sh <<EOF
#!/bin/bash
set -euxo pipefail
sudo -u postgres psql -c "SELECT setval('shipments_shipment_id_seq', COALESCE((SELECT MAX(shipment_id) + 1 FROM shipments), 1), false);"
sudo -u postgres psql -c "SELECT setval('products_product_id_seq', COALESCE((SELECT MAX(product_id) + 1 FROM products), 1), false);"
EOF

if [ -f /usr/local/bin/fix-postgres.sh ]; then
    echo "[INFO] fix-postgres.sh exists."
    chmod +x /usr/local/bin/fix-postgres.sh
fi
CREATE DATABASE IF NOT EXISTS retail;
USE retail;

DROP TABLE IF EXISTS raw_retail;

CREATE TABLE raw_retail (
  Invoice TEXT,
  StockCode TEXT,
  Description TEXT,
  Quantity TEXT,
  InvoiceDate TEXT,
  Price TEXT,
  CustomerID TEXT,
  Country TEXT
);

-- latin1 avoids Error 1300 on the special characters in some product descriptions
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/raw_retail.csv'
INTO TABLE raw_retail
CHARACTER SET latin1
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

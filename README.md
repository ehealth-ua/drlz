# DRLZ

[![Hex pm](http://img.shields.io/hexpm/v/drlz.svg?style=flat)](https://hex.pm/packages/drlz)

Даунлоадер FHIR таблиць Державного Реєстру Лікрських Засобів https://drlz.info/api/docs у вигляді CSV файлів на 150 рядків як http://hex.pm пакет.

## Features

* Network Error Prune CSV Downloader
* Proper Restart Support

## How to use?

Run using Elixir:

```
$ sudo apt install erlang elixir
$ git clone git@github.com:ehealth-ua/drlz
$ cd drlz
$ mix deps.get
$ export DRLZ=$DRLZ_JWT_BEARER
$ iex -S mix
```

Follow Logs:

```
$ tail -f drlz.log
```

Copy Data:

```
$ ls -l priv/2025-08-07
total 31500
-rw-r--r-- 1 tonpa tonpa  7406625 Aug  7 13:34 forms.csv
-rw-r--r-- 1 tonpa tonpa 14673534 Aug  7 12:12 ingredients.csv
-rw-r--r-- 1 tonpa tonpa  2338654 Aug  7 13:05 licenses.csv
-rw-r--r-- 1 tonpa tonpa  1067546 Aug  7 13:06 organizations.csv
-rw-r--r-- 1 tonpa tonpa  2799766 Aug  7 12:22 packages.csv
-rw-r--r-- 1 tonpa tonpa  2611173 Aug  7 12:44 products.csv
-rw-r--r-- 1 tonpa tonpa  1346909 Aug  7 12:49 substances.csv

```

## Credits

Максим Сохацький

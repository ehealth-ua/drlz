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
$ ls -l priv/2025-08-06
total 20320
-rw-r--r-- 1 tonpa tonpa    24503 Aug  7 01:23 forms.csv
-rw-r--r-- 1 tonpa tonpa 14526012 Aug  6 18:38 ingredients.csv
-rw-r--r-- 1 tonpa tonpa   469872 Aug  7 01:12 licenses.csv
-rw-r--r-- 1 tonpa tonpa  1066606 Aug  7 01:26 organizations.csv
-rw-r--r-- 1 tonpa tonpa   733326 Aug  7 00:58 packages.csv
-rw-r--r-- 1 tonpa tonpa  2622337 Aug  6 21:00 products.csv
-rw-r--r-- 1 tonpa tonpa  1349049 Aug  6 19:55 substances.csv
```

## Credits

Максим Сохацький

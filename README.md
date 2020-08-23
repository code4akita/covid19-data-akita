# COVID-19 Data Akita

秋田県が以下のページで公表している新型コロナウイルス感染症に関する情報から、オープンデータとして活用できるJSONファイルを生成しS3バケットにアップロードします。 

- [新型コロナウイルス感染症に係る入退院者数・検査実施件数等](https://www.pref.akita.lg.jp/pages/archive/51592)
- [新型コロナウイルス感染者関連の情報について](https://www.pref.akita.lg.jp/pages/archive/47957)


## データ公開

生成したファイルは次のURLで公開しています。   
YYYYには年が、MMには月が、DDには日が入り、閲覧したい日付に合わせて置き換えてください。  
月、日が1桁の場合は0を前に足してください。(8 -> 08)

https\://covid19-akita.s3.amazonaws.com/YYYY/MM/DD.json

例:  2020年8月23日
[https://covid19-akita.s3.amazonaws.com/2020/08/23.json](https://covid19-akita.s3.amazonaws.com/2020/08/23.json)

※) データは2020年8月23日からの公開で以前のデータはありません。

## 使い方

AWSのS3にファイルをアップロードしますので、S3が使える様に前準備してください。

.envファイルにS3のバケット名とアクセスキーIDとシークレットアクセスキーを設定します。  
sample.envファイルを参考にしてください。

```
$ cp sample.env .env
$ vi .env
```

.env

```
AWS_BUCKET=YOUR_S3_BUCKET_NAME
AWS_ACCESS_KEY_ID=YOUR_AWS_ACCESS_KEY
AWS_SECRET_ACCESS_KEY=YOUR_AWS_SECRET_ACCESS_KEY
```

Gemをインストールします。

```
$ bundle install
```

rake コマンドでJSONファイルを生成しS3の指定バケットにアップロードします。

```
$ rake update:json
````


## ライセンス

MIT

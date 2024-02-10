## Description
Run automated website tests, set in values.yaml. Check URLs against status codes, expected CSS selectors, redirects.

# Example values.yaml
```
require:
- path: /
  statusCode: 200
  cssSelectors:
	- key: "title"
	  value: "Value expected"
	- key: "footer"
```

## Our Use Case
We use this in-house to test our website after each update, before deploying to production. This way all updates are 
done automatically, and we can be sure that the website is still working as expected.

## Adding Plugins
This chart is designed to be extensible. Simply add your own script to ./plugins/*.sh. You can then add the commands via
values.yaml.

Example:
```
plugins:
  downloader:
    - url: google.com
      fetch:
        - jpg
        - png
```
Will run
```
/plugins/downloader.sh --url="google.com" --fetch="jpg" --fetch="png"
```
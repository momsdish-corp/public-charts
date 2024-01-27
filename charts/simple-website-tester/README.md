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
This chart was designed to be extensible. You can add your own plugins to ./plugins/*.sh, and then update cm.yaml.

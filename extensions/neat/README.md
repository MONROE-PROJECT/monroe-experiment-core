# monroe neat extension
Enables the use of NEAT in monroe.

This extension adds a Neat Proxy that can be controlled from the experiment container.
Currently only TCP is supported.

## Rationale
To be able to do neat experiments in Monroe 

## How to use
When Schdeuling add `"neat":1` as a option. eg. `curl --insecure -H 'x-api-key: $3cr3t_Pa$$w0rd!' -d '{ "script": "jonakarl/nodetest", "neat": "1"}' -H "Content-Type: application/json" -X POST https://<HOST>:8080/api/v1.0/experiment/testX/start`

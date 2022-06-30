# Notes during development

## minikube

- `minikube start --driver=docker`
- `kubectl config use-context minikube`
- `docker login`
- `k create deployment watchex --image madclaws/watchex:0.1.1_dev`


- `kubectl expose deployment watchex --type=NodePort --port=4000`
- `k get services`

- `minikube service --url watchex-a -n games`

- `minikube addons enable ingress `

```
alias Discovery.Engine.Builder

{_, {_, bid}} = Builder.start_link

Process.exit(bid, :kill)
```

alias Discovery.Deploy.DeployUtils
depl = %DeployUtils{app_name: "watchex", app_image: "watchex:0.1.4_dev"}

%Discovery.Deploy.DeployUtils{
  app_image: "madclaws/watchex:0.1.4_dev",
  app_name: "watchex"
} 

## service account token

k get serviceaccount -n namespace

Add cluster role binding
`kubectl create clusterrolebinding cluster-system-anonymous --clusterrole=cluster-admin --user=system:anonymous`


or;
`k get secret -n namespace`
`k describe secrets default-token-ch4bm -n namespace`

```
kubectl get secret $secret -o yaml | grep "token:" | awk {'print $2'} |  base64 -d > token
[token] is base64 encoding of jwt present as secret k8s
curl -v -k -H --cacert ~/.minikube/ca.crt -H "Authorization: Bearer $(cat ~/[token])"  "https://192.168.49.2:8443/api/v1/pods" 
```
## Ways of interacting with k8s 

1. k8s client 
  
    client v1.1.5 has apply, build etc apis but
    k8s apply calls this  `K8s.Operation.build(:apply, "/home/ghostdsb/Documents/gamezop/discoveryminikube/discovery/enterprise/ingress.yml", [field_manager: "elixir", force: true])`

2. instead of kubectl in container, use http api.
  
    To use kubectl commands in container we have to install kubectl in container.
    we can install curl instead and hit k8s api
    prerequisites
      - serviceaccount
      - role and role binding for service account
    

https://stackoverflow.com/questions/42642170/how-to-run-kubectl-commands-inside-a-container

## delete deployment

 k get deployment -n discovery
 k delete deployment <name> -n discovery

 ---

# 2022-05-25 11:32:44

### MVP roadmap

- [PROBLEM]Inconsistency in connecting to remote k8s locally via kube config file

1. Authentication using service account.
  - Try to connect locally to dev k8s.
2. Deploying to dev, integrating with tic-tac-toe.
3. Create, delete deployment api.
4. Deploying to prod with tictactoe.

## Service account

  discovery-sa added to namespace discovery with following access
  
    - apiGroups: [""]
      resources: ["pods", "services", "pods/log", "configmaps"]
      verbs: ["get", "watch", "list", "patch", "create"]
    - apiGroups: ["extensions", "apps"]
      resources: ["deployments"]
      verbs: ["get", "list", "watch", "patch", "create"]
    - apiGroups: ["extensions", "networking.k8s.io"]
      resources: ["ingresses"]
      verbs: ["get", "list", "watch", "patch", "create", "update"]

## Prod requirements

  - add serviceAccountName to Deployment spec
  - add imagePullSecrets to Deployment spec
  - add kubernetes.io/ingress.class: nginx-external to ingress annotation

## TODOS

  - ~~app-name becomes a URL hence it should be URL friendly(no underscore or special characters)~~
  - ~~compare patch and update for existing ingress~~
  - ~~create for new ingress~~
  - ~~access of sa for above verbs~~

  - deleting deployment should delete corresponding ingress path


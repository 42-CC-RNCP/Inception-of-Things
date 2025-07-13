# Use Ingress to access the application

Ingress is a Kubernetes resource that manages external access to services in a cluster, typically HTTP. It provides a way to expose your application to the outside world.

## What is the difference between API Gateway and Ingress and Gateway API?



## Gateway API

### API Overview (Roles and CRDs)

```mermaid
sequenceDiagram
    participant Client as Client (Browser / cURL)
    participant Gateway as Gateway<br/>(Traefik Listener 80/443)
    participant Route as HTTPRoute<br/>(app2-route)
    participant Svc as Service<br/>(app2 ClusterIP)
    participant Ep as Endpoints<br/>(app2 Pod IPs)
    participant Deploy as Deployment<br/>(app2 • replicas = 3)

    Client->>Gateway: ① HTTP(S) request<br/>http(s)://app2.com/…
    Gateway-->>Client: TLS termination (if HTTPS)
    Gateway->>Route: ② Delegates via <i>parentRefs</i>
    Route->>Route: ③ Match host/path/header<br/>(hostnames = app2.com)
    Route->>Svc: ④ backendRefs → Service app2
    Svc->>Ep: ⑤ ClusterIP LB picks a Pod IP
    Ep->>Deploy: ⑥ Pod belongs to Deployment app2
    Deploy-->>Ep: ⑦ ReplicaSet maintains 3 running Pods
    Ep-->>Svc: ⑧ Endpoints list kept up to date
    Svc-->>Client: ⑨ Response forwarded back through Gateway

```

### How the config works




#A simplex solver for linear programming problem in (N)SIMULE
.wlinprogSPar <- function(i, Sigma, W, lambda){
  # num of p * N
  # pTimesN = nrow(Sigma)
  # num of p * (N + 1)
  # Get parameters
  q = ncol(Sigma)
  p = ncol(Sigma) - nrow(Sigma)
  N = nrow(Sigma) / p
  # Generate e_j
  e = rep(0, p * N)
  for(j in 1:N){
    e[i + (j - 1) * p] = 1
  }
  # linear programming solution
  f.obj = rep(W[i, ], 2 * (N+1))
  con1 = cbind(-Sigma, +Sigma)
  b1 = lambda - e
  b2 =  lambda + e
  f.con = rbind(-diag(2 * q), con1, -con1)
  f.rhs = c(rep(0, 2 * q), b1, b2)
  f.dir = rep("<=", length(f.rhs))
  lp.out = lp("min", f.obj, f.con, f.dir, f.rhs)
  beta = lp.out$solution[1:q] - lp.out$solution[(q + 1):(2 * q)]
  if (lp.out$status == 2) warning("No feasible solution!  Try a larger tuning parameter!")
  return(beta)
}

# (N)SIMULE implementation
wsimule <- function(X, lambda, epsilon = 1, W, covType = "cov",parallel = FALSE ){

  if (is.data.frame(X[[1]])){
    for (i in 1:(length(X))){
      X[[i]] = as.matrix(X[[i]])
    }
  }

  #get number of tasks
  N = length(X)
  #get the cov/cor matrices
  if (isSymmetric(X[[1]]) == FALSE){
    try(if (covType %in% c("cov","kendall") == FALSE) stop("The cov/cor type you specifies is not include in this package. Please use your own function to obtain the list of cov/cor and use them as the input of simule()"))
    if (covType == "cov")
    {
      for (i in 1:N){
        X[[i]] = cov(X[[i]])
      }
    }
    if (covType == "kendall"){
      for(i in 1:N){
        X[[i]] = cor.fk(X[[i]])
      }
    }
  }
  # initialize the parameters
  Graphs = list()
  p = ncol(X[[1]])
  if (missing(W)){
    W = matrix(1, p, p)
  }
  xt = matrix(0, (N + 1) * p, p)
  I = diag(1, p, p)
  Z = matrix(0, p, p)
  # generate the condition matrix A
  A = X[[1]]
  for(i in 2:N){
    A = cbind(A,Z)
  }
  A = cbind(A,(1/(epsilon * N))*X[[1]])
  for(i in 2:N){
    temp = Z
    for(j in 2:N){
      if (j == i){
        temp = cbind(temp,X[[i]])
      }
      else{
        temp = cbind(temp,Z)
      }
    }
    temp = cbind(temp, 1/(epsilon * N) * X[[i]])
    A = rbind(A, temp)
  }
  # define the function f for parallelization
  f = function(x) .wlinprogSPar(x, A, W, lambda)

  if(parallel == TRUE){ # parallel version
    # number of cores to collect,
    # default number is number cores in your machine - 1,
    # you can set your own number by changing this line.
    no_cores = detectCores() - 1
    cl = makeCluster(no_cores)
    # declare variable and function names to the cluster
    clusterExport(cl, list("f", "A", "W", "lambda", ".linprogSPar", "lp"), envir = environment())
    result = parLapply(cl, 1:p, f)
    #print('Done!')
    for (i in 1:p){
      xt[,i] = result[[i]]
    }
    stopCluster(cl)
  }else{ # single machine code
    for (i in 1 : p){
      xt[,i] = f(i)
      if (i %% 10 == 0){
        cat("=")
        if(i %% 100 == 0){
          cat("+")
        }
      }
    }
    print("Done!")
  }

  for(i in 1:N){
    # combine the results from each column. (\hat{\Omega}_{tot}^1)
    Graphs[[i]] = xt[(1 + (i-1) * p):(i * p),] + 1/(epsilon * N) * xt[(1 + N * p):((N + 1) * p),]
    # make it be symmetric
    for(j in 1:p){
      for(k in j:p){
        if (abs(Graphs[[i]][j,k]) < abs(Graphs[[i]][k,j])){
          Graphs[[i]][j,k] = Graphs[[i]][j,k]
          Graphs[[i]][k,j] = Graphs[[i]][j,k]
        }
        else{
          Graphs[[i]][j,k] = Graphs[[i]][k,j]
          Graphs[[i]][k,j] = Graphs[[i]][k,j]
        }
      }
    }
  }
  share = 1/(epsilon * N) * xt[(1 + N * p):((N + 1) * p),]
  for(j in 1:p){
    for(k in j:p){
      if (abs(share[j,k]) < abs(share[k,j])){
        share[j,k] = share[j,k]
        share[k,j] = share[j,k]
      }
      else{
        share[j,k] = share[k,j]
        share[k,j] = share[k,j]
      }
    }
  }
  out = list(Graphs = Graphs, share = share)
  class(out) = "wsimule"
  return(out)
}

plot.wsimule <-
  function(x, type="graph", subID=NULL, index=NULL, ...)
  {
    .env = "environment: namespace:simule"
    #UseMethod("plot")
    tmp = x$Graphs
    Graphs = list()
    p = dim(tmp[[1]])[1]
    if (type == "share"){
      Graphs[[1]] = x$share
    }
    if (type == "sub"){
      Graphs[[1]] = tmp[[subID]] - x$share
    }
    if (type == "graph"){
      Graphs = tmp
    }
    if (type == "neighbor"){
      id = matrix(0,p,p)
      id[index,] = rep(1,p)
      id[,index] = rep(1,p)
      for (i in 1:length(tmp)){
        Graphs[[i]] = tmp[[i]] * id
      }
    }
    K=length(Graphs)
    adj = .make.adj.matrix(Graphs)
    diag(adj)=0
    gadj = graph.adjacency(adj,mode="upper",weighted=TRUE)
    #weight the edges according to the classes they belong to
    E(gadj)$color = 2^(K)-get.edge.attribute(gadj,"weight")
    #plot the net using igraph
    plot(gadj, vertex.frame.color="white",layout=layout.fruchterman.reingold,
         vertex.label=NA, vertex.label.cex=3, vertex.size=1)
  }

.make.adj.matrix <-
  function(theta, separate=FALSE)
  {
    K = length(theta)
    adj = list()
    if(separate)
    {
      for(k in 1:K)
      {
        adj[[k]] = (abs(theta[[k]])>1e-5)*1
      }
    }
    if(!separate)
    {
      adj = 0*theta[[1]]
      for(k in 1:K)
      {
        adj = adj+(abs(theta[[k]])>1e-5)*2^(k-1)
      }
    }
    return(adj)
  }
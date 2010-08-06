%
%  rho = tilqr_poly_verify(x,u,f,x0,u0,K,S,options)
%
%  Verifies that the region:
%     { x | (x-x0)'S(x-x0) <= rho }
%  Under the dynamics:
%     d/dt x = f(x,Sats(u0-K(x-x0)))
%  is exponentially stable.  Sats is a set of saturations set in
%  the options data structure.
%
%  x  -- n-by-1 free msspoly 
%  u  -- m-by-1 free msspoly
%  f  -- n-by-1 msspoly in x and u
%  x0 -- n-by-1 equilibirum position.
%  u0 -- m-by-1 nominal command.
%  K  -- m-by-n feedback gain.
%  S  -- n-by-n positive definite matrix defining quadratic
%        Lyap. function.
%  options:
%  epsilon -- Convergence rate for exponential stability.
%  Umax -- m-by-1 upper limit on commands.
%  Umin -- m-by-1 lower limit on commands.
%
function rho = roa_tilq_poly(x,u,f,x0,u0,K,S,options)
    if size(x0,1) ~= size(x,1), error('x and x0 do not match.'); end
    if size(u0,1) ~= size(u,1), error('u and u0 do not match.'); end
    nx = size(x0,1);
    nu = size(u0,1);
    
    if nargin < 8, options = struct(); end
    if ~isfield(options,'epsilon'), options.epsilon = 1e-3; end
    if options.epsilon < 0, error(['options.epsilon must be ' ...
                            'non-negative.']); end
    
    if size(x0,2) ~= 1, error('x0 must be a column.'); end
    if size(u0,2) ~= 1, error('u0 must be a column.'); end
    if size(S) ~= [nx nx], error('S size does not match.'); end
    if size(K) ~= [nu nu], error('K size does not match.'); end
    
    V   = x'*S*x;  % Lyapunov Function
    W   = options.epsilon*V;    

    if size(f) ~= [nx 1]
        error(['f(x,u) does not return appropriate size']); 
    end
    
    if ~isfield(options,'Umax'), options.Umax = repmat(Inf,nu,1); end
    if ~isfield(options,'Umin'), options.Umin = repmat(-Inf,nu,1); end
    if options.Umin >= options.Umax, 
        error('Saturation bounds not ordered.'); 
    end
    if any(options.Umax == u0) || any(options.Umin == u0)
        error(['The nominal command cannot be on the boundary ' ...
               'of saturation.  Submit this as a feature request!']);
    end
    
    ui = [];
    gi = [];
    
    for i = 1:nu
        if options.Umax(i) < Inf  %  u0-Kx >= umax
            gmax = options.Umax(i) - (u0(i)-K(i,:)*x);
        else, gmax = []; end
        
        if options.Umin(i) > -Inf  %  umin => u0-Kx
            gmin = u0(i)-K(i,:)*x-options.Umin(i);
        else, gmin = []; end
        
        if ~isempty(gmax) && ~isempty(gmin)
            g  = [  -gmax   -gmin ; gmax 0 ; gmin 0];
            us = [ u0(i)-K(i,:)*x ; options.Umax(i) ; options.Umin(i)];
        elseif ~isempty(gmax)
            g = [  -gmax ; gmax];
            us = [ u0(i)-K(i,:)*x ; options.Umax(i)];
        elseif ~isempty(gmin)
            g = [  -gmin ; gmin];
            us = [ u0(i)-K(i,:)*x ; options.Umin(i)];
        else, g = [ 0 ]; us = u0(i)-K(i,:)*x; end

        if isempty(gi), gi = g; ui = us;
        else
            Idx = repmat(1:size(gi,1),size(g,1),1);
            gi = [ gi(Idx(:),:) repmat(g,size(gi,1),1)];
            ui = [ ui(Idx(:),:) repmat(us,size(ui,1),1)];
        end
    end

    rhoi = zeros(size(gi,1),1);
    fi = 0*repmat(x,1,size(gi,1));
    % Build rhoi and fi

    for i = 1:size(gi,1)
        g = gi(i,:)';
        us = ui(i,:)';
        if double(g) ~= 0
            A = double(diff(g,x));
            b = double(subs(g,x,0*x));
            rhoi(i) = saturation_qp(S,double(0*x),A,-b);
        else
            rhoi = 0;
        end
        fi(:,i) = subss(f,[x;u],[x+x0;us]);
    end

    pi = diff(V,x)*fi + W;
    
    origin = find(prod(double(double(subs(gi,x,0*x)) <= 0),2));
    if length(origin) > 1, 
        error(['Programming Error: origin in more ' ...
               'than one polytope.']); 
    end

    p0 = pi(origin);
    
    if ~all(double(subs(p0,x,0*x)) == 0)
        error('x0 is not an equilibrium.');
    end

    if max(eig(double(subs(diff(diff(p0,x)',x),x,0*x)))) >= 0
        error(['Origin is not exponentially stable (maybe adjust ' ...
               'options.epsilon):' num2str(max(eig(double(subs(diff(diff(p0,x)',x),x,0*x)))))]);
    end

    rho = roa_locus_regions_test(x,V,pi',gi,rhoi);
end

% Determine rho at which the controller enters a particular
% saturation condition.
function rhoi = saturation_qp(Q,xc,A,b)
    xstar = quadprog(Q,-Q*xc,A,b,[],[],[],[],[],optimset('LargeScale','off'));
    rhoi = (xstar-xc)'*Q*(xstar-xc);
end



%  
% rho = locus_region_test(V,p,g0,gi,rhoi,Lmonom,Mmonom)
%
%  V    -- 1-by-1 msspoly.
%  p0   -- 1-by-1 msspoly
%  pi   -- l-by-1 msspoly.
%  gi   -- l-by-K msspoly.
%  rhoi -- l-by-1 positive numbers
%
%
function rho = roa_locus_regions_test(x,V,pi,gi,rhoi)
    if nargin < 5
        error('See Usage.');
    end

    [rhoi,I] = sort(rhoi);
    pi = pi(I,:);
    gi = gi(I,:);
    
    
    l = size(pi,1);

    if any(l ~= [size(gi,1) size(rhoi,1)]) ||...
                any(1 ~= [size(pi,2) size(rhoi,2)])
        error('Sizes do not match.');
    end
    
    rho = Inf;
    i = 1;
    while i <= l && rho > rhoi(i) 
        g = gi(i,:);
        msk = zeros(size(g));
        for j = 1:length(g)
            msk(j) =  double(g(j)) ~= 0; 
        end
        g = g(logical(msk));
        
        rho = roa_locus_region_test(x,V,pi(i),g');
        i = i+1;
    end
end



%  
% rho = locus_region_test(V,p,g,Lmonom,Mmonom)
%
%  V -- 1-by-1 msspoly.
%  p -- 1-by-1 msspoly.
%  g -- k-by-1 msspoly.
%
%  Attempts to max. rho subject to:
%  x ~= 0, p(x) = 0, g(x) <= 0 ==> V(x) > rho.
%
function rho = roa_locus_region_test(x,V,p,g,Lmonom,Mmonom)
    if nargin < 4, g = []; end

    if ~isempty(g) && size(g,2) ~= 1, error('g must be k-by-1.'); end
        
    k = size(g,1);

    prog = mssprog;
    
    rho = msspoly('r');
    prog.free = rho;

    if nargin < 5 % Just a guess.
        Lmonom = monomials(x,0:deg(p,x));
    end
    
    [prog,l] = new(prog,length(Lmonom),'free');
    L = l'*Lmonom;
    
    % origin is in feasible set.
    if all(double(subs(g,x,0*x)) <= 0) 
        w = x'*x;
    else, w = 1; end

    if k > 0
        if nargin < 6
            Mmonom = repmat(monomials(x,0:2*deg(p,x)-deg(g,x)),1,k);
        end
        [prog,m] = new(prog,prod(size(Mmonom)),'free');
        M = sum(reshape(m,size(Mmonom,1),size(Mmonom,2)).*Mmonom,1);
        
        prog.sos = M;
        prog.sos = w*(V - rho) + M*g +  L*p;
    else
        prog.sos = w*(V - rho) +  L*p;
    end

    [prog,info] = sedumi(prog,-rho);
    if info.dinf ~= 0
        rho = Inf;
    else
        rho = double(prog(rho));
    end
end
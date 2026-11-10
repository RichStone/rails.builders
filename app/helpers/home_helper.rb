module HomeHelper
  ANONYMOUS_ADJECTIVES = %w[
    Algorithmic Array-Backed Asynchronous Atomic Backpropagating Backtracking Big-Endian Binary Bitwise Bloom-Filtered
    Branchless Buffered Byte-Sized Cache-Friendly Cacheable Canonicalized Chunked Cloud-Native Clustered Compiled
    Compressed Concurrent Constant-Time Containerized Continuation-Passing Cryptographic Cybernetic Data-Driven Deadlock-Free Debuggable
    Declarative Deduplicated Deferred Deterministic Differentiable Distributed Dockerized Dynamic Eager-Loaded Edge-Ready
    Encrypted Event-Driven Fault-Tolerant Federated Forked Full-Stack Functional Fuzzed Garbage-Collected Git-Powered
    GraphQL-Powered Hashable Headless Heap-Allocated Hot-Reloaded Hyperlinked Idempotent Immutable Indexed Inlined
    Interpreted Interrupt-Driven Iterative JIT-Compiled Kernel-Level Lambda-Powered Lazy-Loaded Lock-Free Memoized Memory-Safe
    Modular Multithreaded Neural Nullable Object-Oriented Observable Optimized Overclocked Packet-Switched Parallel
    Polymorphic Quantized Quantum Queueable Rate-Limited Reactive Recursive Refactored Regex-Powered Replicated
    Resilient Sandboxed Scalable Schemaless Serverless Sharded Signed Stateful Stateless Streamed
    Synchronized Tail-Recursive Test-Driven Tokenized Transactional Transpiled Typed Vectorized Versioned Virtualized
  ].freeze

  ANONYMOUS_NOUNS = %w[
    Bagel Biscuit Burrito Carrot Churro Cobbler Cookie Croissant Crouton Cupcake
    Dumpling Falafel Fig Fritter Gnocchi Guacamole Hot\ Dog Jalapeño Jelly\ Bean Kimchi
    Lemon Mango Mochi Noodle Olive Pancake Peanut Pickle Pierogi Pineapple
    Popcorn Pretzel Ravioli Samosa Taco Waffle
    Arc Bead Bubble Circle Cone Crescent Cube Dodecahedron Dome Ellipse
    Fractal Helix Hexagon Icosahedron Knot Möbius\ Strip Octagon Orbit Oval Parabola
    Pentagon Polygon Prism Pyramid Rectangle Rhombus Ring Sphere Spiral Square
    Star Tetrahedron Torus Trapezoid Triangle Vortex
    Arbitrage Bargain Bear\ Market Bid Bond Bull\ Market Cash\ Cow Coin Coupon Credit
    Dividend Downtick Equity Futures Gold\ Rush Hedge Index Inflation Ledger Liquidity
    Market\ Cap Monopoly Nickel Option Paycheck Premium Quota Rally Rebate Rent
    Surplus Tariff Tradeoff Treasury Windfall Yield\ Curve
  ].freeze

  def anonymous_builder_name(builder)
    key = Rails.application.key_generator.generate_key("private-builder-alias", 32)
    seed = OpenSSL::HMAC.hexdigest("SHA256", key, builder.id.to_s).to_i(16)
    random = Random.new(seed)
    [ ANONYMOUS_ADJECTIVES.sample(random:), ANONYMOUS_NOUNS.sample(random:) ].join(" ")
  end
end

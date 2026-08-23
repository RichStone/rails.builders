module HomeHelper
  ANONYMOUS_ADJECTIVES = %w[
    Nerdy 42ish Algorithmic APIFirst Async Atomic Automated BandwidthRich BigEndian Binary
    Bitwise Blockchainy Bootstrapped Branchless Buffered ByteSized CacheFriendly CloudNative CodeComplete Compiling
    Composable Computed Concurrent Containerized CronPowered CryptoCurious Cybernetic DataDriven Debuggable Declarative
    Deterministic DevOpsy Distributed Dockerized Dynamic EdgeReady Elegant Encrypted EventDriven FaultTolerant
    FullStack Functional GarbageCollected GitPowered GraphQLish Hackable Headless HotReloaded Hyperlinked Idempotent
    Immutable Indexed Iterative KernelLevel LambdaPowered LatencyAware LazyLoaded LogicDriven Loopy MachineLearned
    MemorySafe Meta Microserviced Modular MultiThreaded Neural NullSafe ObjectOriented Observable OpenSource
    Overclocked PacketSized Parallel PixelPerfect Polymorphic PromptDriven Quantum Recursive Refactored RegexPowered
    Resilient RESTful RubyPowered Scalable Schemaless Serverless ShellReady ShipShape Signed Stateful
    Stateless Streamed Sudo Synced TestDriven Tokenized Typed Unixy Versioned ZeroDowntime
  ].freeze

  ANONYMOUS_FIRST_NAMES = %w[
    Ada Alan Grace Linus Margaret Tim Guido Yukihiro Brendan James
    Dennis Ken Brian Bjarne Barbara Donald Edsger John Steve Bill
    Elon Mark Larry Sergey Jeff Satya Susan Radia Hedy Annie
    Katherine Mary Evelyn Jean Frances Adele Karen Sophie Carol Lynn
    Rasmus Anders Miguel Mitchell Martin Robert Ward Kent Rebecca Leah
    Fei-Fei Demis Geoffrey Yann Andrew Andrej Sam Ilya Mira Jensen
    Lisa Marissa Sheryl Whitney Melanie Reshma Kimberly Joy Tanmay Arvind
    David Jason Aaron Matz José Xavier Mina Sandi Avdi Chad
    Joel Yehuda Tobias Sarah Sara Jessica Julie Taylor Alex Jordan
    Casey Morgan Riley Jamie Cameron Quinn Robin Terry Drew Skyler
  ].freeze

  ANONYMOUS_LAST_NAMES = %w[
    Lovelace Turing Hopper Torvalds Hamilton BernersLee VanRossum Matsumoto Eich Gosling
    Ritchie Thompson Kernighan Stroustrup Liskov Knuth Dijkstra Carmack Jobs Wozniak
    Gates Musk Zuckerberg Page Brin Bezos Nadella Wojcicki Perlman Lamarr
    Easley Johnson Jackson Sammet Goldstine Mahoney Goldberg Allen Kay Engelbart
    McCarthy Shannon Boole Babbage Clarke Cerf Kahn Metcalfe Stallman Wall
    Hejlsberg Odersky Hickey Dahl Nygaard Ingalls Pike Joy Rubin Hansson
    Dorsey Systrom Krieger Koum Acton Hoffman Williams Rometty Su Huang
    Amodei Hassabis Hinton LeCun Ng Karpathy Altman Sutskever Murati Pichai
    Sandberg Mayer Bresch Harts Mistry Shah Fried Spolsky Atwood Zakas
    Fowler Beck Gamma Helm Vlissides Martin Feathers Meszaros DeMarco Brooks
  ].freeze

  def anonymous_builder_name(builder)
    random = Random.new(builder.id)
    [
      ANONYMOUS_ADJECTIVES.sample(random:),
      ANONYMOUS_FIRST_NAMES.sample(random:),
      ANONYMOUS_LAST_NAMES.sample(random:)
    ].join(" ")
  end
end

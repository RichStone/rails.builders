# Google API DEBUG responses include authenticated request headers.
Google::Apis.logger = Logger.new($stdout, level: Logger::INFO)

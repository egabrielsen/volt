module Volt
  class Computation
    @@current     = nil
    @@flush_queue = []

    def self.current=(val)
      @@current = val
    end

    def self.current
      @@current
    end

    def initialize(computation)
      @computation   = computation
      @invalidations = []
    end

    # Runs the computation
    def compute!
      @invalidated = false

      unless @stopped

        @computing = true
        run_in do
          @computation.call
        end
        @computing = false
      end
    end

    def on_invalidate(&callback)
      if @invalidated
        # Call invalidate now, since its already invalidated
        Computation.run_without_tracking do
          callback.call
        end
      else
        # Store the invalidation
        @invalidations << callback
      end
    end

    # Calling invalidate removes the computation from all of
    # its dependencies.  This keeps its dependencies from
    # invalidating it again.
    def invalidate!
      unless @invalidated
        @invalidated = true

        unless @stopped || @computing
          @@flush_queue << self

          # If we are in the browser, we queue a flush for the next tick
          if Volt.in_browser?
            self.class.queue_flush!
          end

          # If we are not in the browser, the user must manually flush
        end

        invalidations  = @invalidations
        @invalidations = []

        invalidations.each(&:call)
      end
    end

    # Stop re-run of the computations
    def stop
      unless @stopped
        @stopped = true
        invalidate!
      end
    end

    # Runs in this computation as the current computation, returns the computation
    def run_in
      previous            = Computation.current
      Computation.current = self
      yield
      Computation.current = previous
      self
    end

    # Run a block without tracking any dependencies
    def self.run_without_tracking
      previous            = Computation.current
      Computation.current = nil
      begin
        return_value        = yield
      ensure
        Computation.current = previous
      end
      return_value
    end

    def self.flush!
      fail "Can't flush while in a flush" if @flushing

      @flushing = true
      # clear any timers
      @timer    = nil

      computations  = @@flush_queue
      @@flush_queue = []

      computations.each(&:compute!)

      @flushing = false
    end

    def self.queue_flush!
      unless @timer
        # Flush once everything else has finished running
        @timer = `setImmediate(function() { self['$flush!'](); });`
      end
    end
  end
end

class Proc
  def watch!
    computation = Volt::Computation.new(self)

    computation.run_in do
      # run self, pass in computation if needed
      if arity > 0
        # Pass in the computation so it can be canceled from within
        call(computation)
      else
        call
      end
    end
  end

  # Watches a proc until the value returned equals the passed
  # in value.  When the value matches, the block is called.
  #
  # @param the value to match
  # @return [Volt::Computation] the initial computation is returned.
  def watch_until!(value, &block)
    computation = -> do
      # First fetch the value
      result = self.call

      if result == value
        # Values match

        # call the block
        block.call

        # stop the computation
        computation.stop
      end
    end.watch!

    computation
  end
end

require 'concurrent/synchronized_object'

module Concurrent

  class CyclicBarrier < SynchronizedObject

    Generation = Struct.new(:status)
    private_constant :Generation

    # Create a new `CyclicBarrier` that waits for `parties` threads
    #
    # @param [Fixnum] parties the number of parties
    # @yield an optional block that will be executed that will be executed after
    #  the last thread arrives and before the others are released
    #
    # @raise [ArgumentError] if `parties` is not an integer or is less than zero
    def initialize(parties, &block)
      super(&nil)
      if !parties.is_a?(Fixnum) || parties < 1
        raise ArgumentError.new('count must be in integer greater than or equal zero')
      end
      synchronize do
        @parties = parties
        @action  = block
        ns_next_generation
      end
    end

    # @return [Fixnum] the number of threads needed to pass the barrier
    def parties
      synchronize { @parties }
    end

    # @return [Fixnum] the number of threads currently waiting on the barrier
    def number_waiting
      synchronize { @number_waiting }
    end

    # Blocks on the barrier until the number of waiting threads is equal to
    # `parties` or until `timeout` is reached or `reset` is called
    # If a block has been passed to the constructor, it will be executed once by
    #  the last arrived thread before releasing the others
    # @param [Fixnum] timeout the number of seconds to wait for the counter or
    #  `nil` to block indefinitely
    # @return [Boolean] `true` if the `count` reaches zero else false on
    #  `timeout` or on `reset` or if the barrier is broken
    def wait(timeout = nil)
      synchronize do

        return false unless @generation.status == :waiting

        @number_waiting += 1

        if @number_waiting == @parties
          @action.call if @action
          ns_generation_done @generation, :fulfilled
          true
        else
          generation = @generation
          if ns_wait_until(timeout) { generation.status != :waiting }
            generation.status == :fulfilled
          else
            ns_generation_done generation, :broken, false
            false
          end
        end
      end
    end


    # resets the barrier to its initial state
    # If there is at least one waiting thread, it will be woken up, the `wait`
    # method will return false and the barrier will be broken
    # If the barrier is broken, this method restores it to the original state
    #
    # @return [nil]
    def reset
      synchronize { ns_generation_done @generation, :reset }
    end

    # A barrier can be broken when:
    # - a thread called the `reset` method while at least one other thread was waiting
    # - at least one thread timed out on `wait` method
    #
    # A broken barrier can be restored using `reset` it's safer to create a new one
    # @return [Boolean] true if the barrier is broken otherwise false
    def broken?
      synchronize { @generation.status != :waiting }
    end

    private

    def ns_generation_done(generation, status, continue = true)
      generation.status = status
      ns_next_generation if continue
      ns_broadcast
    end

    def ns_next_generation
      @generation     = Generation.new(:waiting)
      @number_waiting = 0
    end


  end
end

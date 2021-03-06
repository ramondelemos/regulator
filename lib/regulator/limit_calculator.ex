defmodule Regulator.LimitCalculator do
  @moduledoc false
  # The limit calculator periodically wakes up, fetches all of the latencies
  # in the buffers and calculates the new concurrency limit based on the specified
  # limit algorithm. The default time window is 1 second. But if the maximum
  # number of events is not present in the buffers than we'll wait for another
  # time window before processing.
  use GenServer

  alias Regulator.Buffer
  alias Regulator.Limits
  alias Regulator.Window
  alias Regulator.Telemetry

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(data) do
    schedule()

    {:ok, data}
  end

  def handle_info(:calculate, state) do
    window =
      state.buffer
      |> Buffer.flush_latest
      |> Enum.reduce(Window.new(), fn entry, window -> Window.add(window, entry) end)

    current_limit = Limits.limit(state.limits)
    {mod, opts} = state.limit
    {opts, new_limit} = mod.update(opts, current_limit, window)

    Limits.set_limit(state.limits, new_limit)
    Telemetry.event(:limit, %{limit: new_limit}, %{regulator: state.name})
    state = %{state | limit: {mod, opts}}

    schedule()

    {:noreply, state}
  end

  defp schedule(timeout \\ 1_000) do
    # next time = min(max(min_time * 2, 1_000), 1_000)
    # If our minimum requests are taking way longer than 1 second than don't try
    # schedule another
    Process.send_after(self(), :calculate, timeout)
  end
end

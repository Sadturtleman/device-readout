using System.Diagnostics;

internal static class TestCompletion
{
    // Observe native-boundary completion separately from the SDK's nonjoining stream termination.
    internal static async Task Until(Func<bool> condition, string expectation)
    {
        var elapsed = Stopwatch.StartNew();
        while (!condition()) {
            if (elapsed.Elapsed > TimeSpan.FromSeconds(2)) throw new TimeoutException(expectation);
            await Task.Delay(5).ConfigureAwait(false);
        }
    }
}

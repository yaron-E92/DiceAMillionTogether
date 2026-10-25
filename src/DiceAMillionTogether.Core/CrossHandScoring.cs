namespace DiceAMillionTogether.Core;

/// <summary>A player owns their own dice and rings even when both contribute to a shared score.</summary>
public enum Player { Host, Guest }

public sealed record ScoringDie(string Id, Player Owner, decimal BaseScore);

/// <summary>
/// A modifier emitted by an item owned by Source. It affects dice owned by Source
/// and by the *other* player separately; multipliers stack multiplicatively.
/// Examples: Generous Die = 0.5 own / 3 partner.
/// </summary>
public sealed record CrossHandModifier(
    string Id,
    Player Source,
    decimal OwnMultiplier,
    decimal PartnerMultiplier);

public sealed record ScoredDie(string Id, Player Owner, decimal BaseScore, decimal Multiplier, decimal FinalScore);

public sealed record ScoringResult(IReadOnlyList<ScoredDie> Dice, decimal HostScore, decimal GuestScore)
{
    public decimal SharedScore => HostScore + GuestScore;
}

/// <summary>
/// Pure deterministic scoring rules. This does not alter GameMaker's native ring
/// interactions yet; it is a testable foundation for migrating those effects.
/// </summary>
public static class CrossHandScoring
{
    public static ScoringResult Evaluate(
        IEnumerable<ScoringDie> dice,
        IEnumerable<CrossHandModifier> modifiers)
    {
        ArgumentNullException.ThrowIfNull(dice);
        ArgumentNullException.ThrowIfNull(modifiers);

        var rules = modifiers.ToArray();
        foreach (var rule in rules)
        {
            if (string.IsNullOrWhiteSpace(rule.Id))
                throw new ArgumentException("Modifier id must not be empty.", nameof(modifiers));
            if (rule.OwnMultiplier < 0 || rule.PartnerMultiplier < 0)
                throw new ArgumentOutOfRangeException(nameof(modifiers), "Multipliers must be nonnegative.");
            if (!Enum.IsDefined(rule.Source))
                throw new ArgumentException("Unknown modifier owner.", nameof(modifiers));
        }

        var scored = new List<ScoredDie>();
        decimal host = 0;
        decimal guest = 0;
        foreach (var die in dice)
        {
            if (string.IsNullOrWhiteSpace(die.Id))
                throw new ArgumentException("Die id must not be empty.", nameof(dice));
            if (!Enum.IsDefined(die.Owner))
                throw new ArgumentException("Unknown die owner.", nameof(dice));
            if (die.BaseScore < 0)
                throw new ArgumentOutOfRangeException(nameof(dice), "Base score must be nonnegative.");

            decimal multiplier = 1;
            foreach (var modifier in rules)
                multiplier *= die.Owner == modifier.Source
                    ? modifier.OwnMultiplier
                    : modifier.PartnerMultiplier;

            decimal final = die.BaseScore * multiplier;
            scored.Add(new ScoredDie(die.Id, die.Owner, die.BaseScore, multiplier, final));
            if (die.Owner == Player.Host) host += final;
            else guest += final;
        }
        return new ScoringResult(scored, host, guest);
    }

    public static CrossHandModifier GenerousDie(Player owner)
        => new("generous-die", owner, 0.5m, 3m);
}

namespace Sedulous.UI2.Tests;

using System;
using Sedulous.UI2;

class ModelIndexTests
{
	[Test]
	public static void Default_IsInvalid()
	{
		let idx = ModelIndex();
		Test.Assert(!idx.IsValid);
		Test.Assert(idx.Row == -1);
	}

	[Test]
	public static void Invalid_Constant()
	{
		Test.Assert(!ModelIndex.Invalid.IsValid);
	}

	[Test]
	public static void WithRow_IsValid()
	{
		let idx = ModelIndex(0);
		Test.Assert(idx.IsValid);
		Test.Assert(idx.Row == 0);
	}

	[Test]
	public static void Equality_SameRow()
	{
		let a = ModelIndex(5);
		let b = ModelIndex(5);
		Test.Assert(a == b);
	}

	[Test]
	public static void Inequality_DifferentRow()
	{
		let a = ModelIndex(1);
		let b = ModelIndex(2);
		Test.Assert(a != b);
	}
}

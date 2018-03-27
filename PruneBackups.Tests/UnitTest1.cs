using System;
using System.Globalization;
using System.IO;
using System.Linq;
using FakeItEasy;
using NUnit.Framework;

namespace PruneBackups.Tests
{
    public class UnitTest1
    {
        [Test]
        public void AssertOnlyRemovedinCorrectAge()
        {
            var backuppath = "/backup/path";
            var fileserver = A.Fake<IFileRepository>();
            var clock = A.Fake<ISystemTime>();
            var dateTimeOffset = Program.ParseDate("20170701");
            A.CallTo(() => clock.Now)
                .Returns(dateTimeOffset);

            A.CallTo(() => fileserver.PathExists(backuppath))
                .Returns(true);

            var backupsNotToBeRemoved = new[]
            {
                "eventstore_prod_20170502_000000.zip",
                "eventstore_prod_20170503_000000.zip",
                "eventstore_prod_20170504_000000.zip",
                "eventstore_prod_20170505_000000.zip",
                "eventstore_prod_20170506_000000.zip",
                "wehatever.zip"
            };
            var backupsToBeRemoved = new[]
            {
                "eventstore_prod_20170401_000000.zip",
                "eventstore_prod_20170402_000000.zip",
                "eventstore_prod_20170403_000000.zip",
                "eventstore_prod_20170404_000000.zip",
                "eventstore_prod_20170405_000000.zip",
                "eventstore_prod_20170406_000000.zip"
            };

            A.CallTo(() => fileserver.GetFiles(backuppath))
                .Returns(backupsNotToBeRemoved.Concat(backupsToBeRemoved));

            Program.FileRepository = fileserver;
            Program.SystemTime = clock;


            Program.Main($"--path {backuppath} --age 60".Split(" "));

            foreach (var backupFile in backupsToBeRemoved)
            {
                A.CallTo(() => fileserver.Delete(backupFile))
                    .MustHaveHappenedOnceExactly();
            }
            foreach (var backupFile in backupsNotToBeRemoved)
            {
                A.CallTo(() => fileserver.Delete(backupFile))
                    .MustNotHaveHappened();
            }
        }
        [Test]
        public void AssertNotThowsWhenEmpty()
        {
            Assert.DoesNotThrow(() => Program.Main(new string[] { }));
        }
        [Test]
        public void AssertReturnsWhenPathNotExist()
        {
            var fileserver = A.Fake<IFileRepository>();
            A.CallTo(() => fileserver.PathExists(A<string>._))
                .Returns(false);

            Program.FileRepository = fileserver;

            Assert.DoesNotThrow(() => Program.Main($"--path /path/does/not/exist --age 60".Split(" ")));

            A.CallTo(() => fileserver.GetFiles(A<string>._))
                .MustNotHaveHappened();
        }
    }
}

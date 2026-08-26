using System;
using System.IO;
using System.Threading.Tasks;
using Windows.Globalization;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;

public class MemoryOcrBridge
{
    public static string DoOcrFromBytes(byte[] bytes)
    {
        return Task.Run(async () =>
        {
            using (var ms = new InMemoryRandomAccessStream())
            {
                using (var writer = new DataWriter(ms.GetOutputStreamAt(0)))
                {
                    writer.WriteBytes(bytes);
                    await writer.StoreAsync();
                    await writer.FlushAsync();
                    writer.DetachStream();
                }
                ms.Seek(0);

                var decoder = await BitmapDecoder.CreateAsync(ms);
                var softwareBitmap = await decoder.GetSoftwareBitmapAsync();

                var engine = OcrEngine.TryCreateFromLanguage(new Language("en-US")) 
                          ?? OcrEngine.TryCreateFromUserProfileLanguages();

                var result = await engine.RecognizeAsync(softwareBitmap);
                return result.Text;
            }
        }).GetAwaiter().GetResult();
    }
}

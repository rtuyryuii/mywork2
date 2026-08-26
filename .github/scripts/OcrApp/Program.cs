using System;
using System.IO;
using System.Threading.Tasks;
using Windows.Globalization;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;

class Program
{
    static async Task<int> Main(string[] args)
    {
        if (args.Length == 0 || !File.Exists(args[0])) return 1;

        try
        {
            byte[] bytes = File.ReadAllBytes(args[0]);
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

                var engine = OcrEngine.TryCreateFromUserProfileLanguages() 
                          ?? OcrEngine.TryCreateFromLanguage(new Language("en-US"));

                var result = await engine.RecognizeAsync(softwareBitmap);
                Console.WriteLine(result.Text);
                return 0;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("ERROR: " + ex.Message);
            return 1;
        }
    }
}

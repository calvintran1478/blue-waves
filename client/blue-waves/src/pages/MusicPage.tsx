import { createResource, Suspense } from "solid-js";
import { api } from "../index.tsx";
import { createAsync, useParams } from "@solidjs/router";
import { getToken } from "../utils/token";

const MusicPage = () => {

    const params = useParams();

    const token = createAsync(() => getToken());

    const [musicFile] = createResource(token, async () => {
        // Get music file
        const musicFileResponse = await api.get(`users/music/${params.music_id}`, {
            headers: {
                "Authorization": `Bearer ${token()}`
            }
        });

        // Decode data as an mp3
        const musicBuffer = await musicFileResponse.arrayBuffer();
        const blob = new Blob([musicBuffer], { type: "audio/mpeg" })
        const url = window.URL.createObjectURL(blob);
        return url;
    });

    const [coverArtFile] = createResource(token, async () => {
        // Get cover art
        const musicArtResponse = await api.get(`users/music/${params.music_id}/cover-art`, {
            headers: {
                "Authorization": `Bearer ${token()}`
            }
        });

        // Decode data as an image
        const imageBuffer = await musicArtResponse.arrayBuffer();
        const blob = new Blob([imageBuffer])
        const url = window.URL.createObjectURL(blob);
        return url;
    })

    return (
        <div class="flex justify-center items-center w-screen h-screen">
            <div class="flex flex-col justify-center items-center aspect-video" style="width: 1080px">
                <Suspense>
                    <video controls poster={coverArtFile()} src={musicFile()}></video>
                </Suspense>
            </div>
        </div>
    )
}

export default MusicPage;

import { createResource, Suspense } from "solid-js";
import { api } from "../index.tsx";
import { useNavigate, useParams } from "@solidjs/router";

const MusicPage = () => {

    const params = useParams();
    const navigate = useNavigate();

    const [token] = createResource(async () => {
        try {
            const tokenResponse = await api.get("users/token", { credentials: "include" }).json<{"access_token": string}>();
            return tokenResponse["access_token"];
        } catch (error) {
            navigate("/login");
        }
    });

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

    return (
        <div class="flex justify-center items-center w-screen h-screen">
            <div class="flex flex-col justify-center items-center aspect-video" style="width: 1080px">
                <Suspense>
                    <video controls src={musicFile()}></video>
                </Suspense>
            </div>
        </div>
    )
}

export default MusicPage;

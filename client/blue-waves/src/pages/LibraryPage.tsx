import { createSignal, createResource, Show } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { api } from "../index.tsx";
import MusicModal from "../components/MusicModal.tsx";

const LibraryPage = () => {
    const [showMusicModal, setShowMusicModal] = createSignal(false);

    const navigate = useNavigate();

    const [token] = createResource(async () => {
        try {
            const tokenResponse = await api.get("users/token", { credentials: "include" }).json<{"access_token": String}>();
            return tokenResponse["access_token"];
        } catch (error) {
            navigate("/login");
        }
    });

    return (
        <div>
            <div>
                <button class="rounded border-2" onClick={() => setShowMusicModal(true)}>Add Music</button>
            </div>
            <Show when={showMusicModal()}>
                <div class="flex justify-center items-center h-screen w-screen fixed inset-0 bg-black/50">
                    <MusicModal token={token() as string} closeCallback={() => setShowMusicModal(false)}/>
                </div>
            </Show>
        </div>
    )
}

export default LibraryPage;

import { createResource, Accessor, Show } from "solid-js";
import { createQuery } from "@tanstack/solid-query";
import { api } from "../index.tsx";
import LoadingSpinner from "../components/LoadingSpinner";

const UpdateMusicModal = (props : { token: string, music_id: Accessor<string>, closeCallback: () => void }) => {
    let artInput!: HTMLInputElement;

    const [coverArtFile] = createResource(props.token, async () => {
        // Get cover art
        const musicArtResponse = await api.get(`users/music/${props.music_id()}/cover-art`, {
            headers: {
                "Authorization": `Bearer ${props.token}`
            }
        });

        // Decode data as an image
        const imageBuffer = await musicArtResponse.arrayBuffer();
        const blob = new Blob([imageBuffer])
        const url = window.URL.createObjectURL(blob);
        return url;
    });

    const setCoverArtQuery = createQuery(() => ({
        queryKey: ["SetCoverArt"],
        queryFn: async () => {
            // Create form data
            const data = new FormData();
            data.append("artFile", artInput.files![0]);

            // Set cover art
            await api.put(`users/music/${props.music_id()}/cover-art`, {
                headers: {
                    "Authorization": `Bearer ${props.token}`
                },
                body: data
            });

            // Close modal
            props.closeCallback();

            return null;
        }
    }));

    const setCoverArt = (event: Event) => {
        event.preventDefault();
        setCoverArtQuery.refetch();
    }

    return (
        <div class="p-6 bg-white" style="width: 60rem; height: 24rem;">
            <div class="flex flex-row-reverse">
                <button onClick={props.closeCallback}>close</button>
            </div>
            <div class="flex justify-around">
                <form onSubmit={setCoverArt} class="flex flex-col justify-center items-center">
                    <input ref={artInput} type="file" id="artFile" class="w-80 m-6 mb-8" required/>
                    <button class="inline-flex items-center border-2 rounded p-3 bg-neutral-400" disabled={setCoverArtQuery.isFetching}>
                        <span class="mr-2">Update music</span>
                        <Show when={setCoverArtQuery.isFetching}>
                            <LoadingSpinner/>
                        </Show>
                    </button>
                </form>
                <img src={coverArtFile()} class="w-80 h-72"/>
            </div>
        </div>
    )
}

export default UpdateMusicModal;

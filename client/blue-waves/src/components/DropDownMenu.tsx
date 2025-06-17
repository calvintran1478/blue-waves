import { createSignal, Show } from "solid-js";

const DropDownMenu = (props: { onSelect: () => void}) => {
    const [toggled, setToggled] = createSignal(false);

    return (
        <div class="flex flex-col">
            <button class="w-12 h-6 border-2" onClick={() => setToggled(!toggled())}>
                Open
            </button>
            <Show when={toggled()}>
                <button class="absolute top-12 right-4 w-16 h-8 border-2" onClick={props.onSelect}>
                    Logout
                </button>
            </Show>
        </div>
    )
}

export default DropDownMenu;
